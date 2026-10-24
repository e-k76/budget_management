import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart' show protected, visibleForTesting;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/app_config.dart';
import '../core/formatters.dart';
import '../models/models.dart';

/// Two-database storage.
///
/// * The **local** database (Desktop folder) is always present and always
///   written.
/// * The **remote** database (DFS share) is written as well whenever it is
///   reachable, and is the one read from while connected.
/// * While the share is unreachable every change is applied locally and also
///   appended to `pending_ops`. When the share comes back the queue is
///   replayed to it in order, then the share's data is mirrored back into the
///   local database (so changes other people made meanwhile are picked up).
///
/// Every mutation is a small named operation applied by [_apply]; the same
/// code runs against both databases and is idempotent so a replay that
/// overlaps a half-finished write cannot duplicate anything. Rows are matched
/// by `uid` / `username` / project name, never by the autoincrement id (which
/// differs between the two files).
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  // -------------------------------------------------------------- listeners

  // Plain-Dart change notification (this file must stay usable from `dart run`
  // tools; the UI wraps it in `DbStatus`, a ChangeNotifier).
  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  @protected
  void notifyListeners() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  // ------------------------------------------------------------ configuration

  @visibleForTesting
  String? localPathOverride;
  @visibleForTesting
  String? remotePathOverride;

  /// Tools (e.g. the Access importer) turn this off to work on one file only.
  @visibleForTesting
  bool remoteEnabled = true;

  /// Tests flip this to simulate the share going away / coming back.
  @visibleForTesting
  bool simulateUnreachable = false;

  String get _localPath => localPathOverride ?? AppConfig.localDbPath;
  String get _remotePath => remotePathOverride ?? AppConfig.remoteDbPath;

  static const _opTimeout = Duration(seconds: 15);
  static const _probeTimeout = Duration(seconds: 4);
  static const _tables = ['users', 'projects', 'expenses', 'incomes', 'settings'];

  // ------------------------------------------------------------------- state

  Database? _local;
  Database? _remote;
  Timer? _timer;
  bool _ticking = false;
  Future<void> _tail = Future.value();

  bool syncing = false;
  int pendingCount = 0;
  String? lastError;
  DateTime? lastSync;

  /// Bumps whenever the data source changes (went online/offline, synced) so
  /// screens know to reload.
  int dataVersion = 0;

  bool get online => _remote != null;
  @visibleForTesting
  Database? get remoteHandle => _remote;

  // ------------------------------------------------------------------ schema

  static const List<String> _schema = [
    '''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('admin', 'manager', 'viewer')),
  created_at TEXT
)''',
    '''
CREATE TABLE IF NOT EXISTS projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  budget_percentage REAL DEFAULT 100.0,
  total_income REAL DEFAULT 0,
  created_at TEXT
)''',
    '''
CREATE TABLE IF NOT EXISTS expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_name TEXT NOT NULL,
  date TEXT NOT NULL,
  amount REAL NOT NULL,
  percentage REAL DEFAULT 0,
  description TEXT,
  payee TEXT,
  uid TEXT,
  is_approved INTEGER DEFAULT 0,
  approved_by TEXT,
  approved_at TEXT,
  created_by TEXT,
  created_at TEXT
)''',
    // Individual income entries; projects.total_income is the running total.
    '''
CREATE TABLE IF NOT EXISTS incomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_name TEXT NOT NULL,
  amount REAL NOT NULL,
  date TEXT NOT NULL,
  uid TEXT,
  created_by TEXT,
  created_at TEXT
)''',
    // Key/value app settings (e.g. the global budget percentage).
    '''
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
    // Changes made while the share was unreachable (only used in the local file).
    '''
CREATE TABLE IF NOT EXISTS pending_ops (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  data TEXT NOT NULL,
  created_at TEXT
)''',
    // Local-only bookkeeping (last successful sync, ...).
    '''
CREATE TABLE IF NOT EXISTS sync_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''',
    'CREATE INDEX IF NOT EXISTS idx_expenses_project ON expenses(project_name)',
    'CREATE INDEX IF NOT EXISTS idx_incomes_project ON incomes(project_name)',
  ];

  /// Upgrades databases created before a column existed.
  static Future<void> _migrate(Transaction txn) async {
    Future<bool> hasColumn(String table, String col) async =>
        (await txn.rawQuery('PRAGMA table_info($table)'))
            .any((c) => c['name'] == col);

    if (!await hasColumn('expenses', 'payee')) {
      await txn.execute('ALTER TABLE expenses ADD COLUMN payee TEXT');
    }
    if (!await hasColumn('expenses', 'approved_at')) {
      await txn.execute('ALTER TABLE expenses ADD COLUMN approved_at TEXT');
    }
    for (final t in ['expenses', 'incomes']) {
      if (!await hasColumn(t, 'uid')) {
        await txn.execute('ALTER TABLE $t ADD COLUMN uid TEXT');
      }
      await txn.execute(
          "UPDATE $t SET uid = lower(hex(randomblob(16))) WHERE uid IS NULL OR uid = ''");
      await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_${t}_uid ON $t(uid)');
    }
    // Rows from the Access import stored "payee — description" in one field.
    await txn.execute('''
UPDATE expenses SET
  payee = trim(substr(description, 1, instr(description, ' — ') - 1)),
  description = trim(substr(description, instr(description, ' — ') + 3))
WHERE created_by = 'Access import' AND payee IS NULL
  AND instr(description, ' — ') > 0
''');
  }

  static bool _ffiReady = false;

  static Future<Database> _open(String path) async {
    if (!_ffiReady) {
      sqfliteFfiInit();
      _ffiReady = true;
    }
    await File(path).parent.create(recursive: true);
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          // These PRAGMAs return a row, so they must go through rawQuery.
          await db.rawQuery('PRAGMA busy_timeout = 5000');
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
        onOpen: (db) async {
          await db.transaction((txn) async {
            for (final sql in _schema) {
              await txn.execute(sql);
            }
            await _migrate(txn);
          });
        },
      ),
    );
  }

  static String _now() => DateTime.now().toIso8601String();

  static String newUid() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ------------------------------------------------------------- life cycle

  Future<Database> _ensureLocal() async => _local ??= await _open(_localPath);

  /// The database reads currently come from (remote when connected).
  Future<Database> get db async => _remote ?? await _ensureLocal();

  /// Opens the local database, starts the connection watcher and tries the
  /// share. The first attempt runs in the background (so an unreachable share
  /// never delays start-up) unless [waitForConnection] is set.
  Future<void> init({bool waitForConnection = false}) async {
    await _locked(() async {
      await _ensureLocal();
      await _refreshPending();
      await _loadLastSync();
    });
    _timer?.cancel();
    if (!remoteEnabled) return;
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => tick());
    final first = tick();
    if (waitForConnection) await first;
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    await _tail.catchError((_) {});
    final r = _remote, l = _local;
    _remote = null;
    _local = null;
    try {
      await r?.close();
    } catch (_) {}
    await l?.close();
    pendingCount = 0;
  }

  Future<T> _locked<T>(Future<T> Function() f) async {
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    try {
      await prev;
    } catch (_) {}
    try {
      return await f();
    } finally {
      done.complete();
    }
  }

  // --------------------------------------------------------------- connection

  Future<bool> _remoteReachable() async {
    if (simulateUnreachable) return false;
    try {
      return await Directory(File(_remotePath).parent.path)
          .exists()
          .timeout(_probeTimeout);
    } catch (_) {
      return false;
    }
  }

  void _goOffline(Object e) {
    lastError = '$e';
    final r = _remote;
    if (r != null) {
      _remote = null;
      r.close().catchError((_) {});
      dataVersion++;
    }
    notifyListeners();
  }

  /// Periodic check: reconnect + sync when the share is back, or notice that
  /// it has gone away.
  Future<void> tick() async {
    if (!remoteEnabled || _ticking || _local == null) return;
    _ticking = true;
    try {
      if (_remote == null) {
        if (!await _remoteReachable()) return;
        await _locked(_connectAndSync);
      } else {
        try {
          if (simulateUnreachable) throw StateError('share unreachable');
          await _remote!.rawQuery('SELECT 1').timeout(_probeTimeout);
          if (pendingCount > 0) await _locked(_sync);
        } catch (e) {
          _goOffline(e);
        }
      }
    } finally {
      _ticking = false;
    }
  }

  /// Manual "sync now".
  Future<void> syncNow() => tick();

  Future<void> _connectAndSync() async {
    if (!remoteEnabled || _local == null) return;
    if (_remote == null) {
      if (!await _remoteReachable()) return;
      try {
        _remote = await _open(_remotePath).timeout(_opTimeout);
        dataVersion++;
        notifyListeners();
      } catch (e) {
        lastError = '$e';
        notifyListeners();
        return;
      }
    }
    await _sync();
  }

  Future<void> _sync() async {
    final remote = _remote, local = _local;
    if (remote == null || local == null) return;
    syncing = true;
    notifyListeners();
    try {
      if (await _hasNoBusinessData(remote)) {
        // A brand-new share: publish this machine's data (incl. users).
        await _copyAll(from: local, to: remote);
        await local.delete('pending_ops');
      } else {
        if (await _meta('last_sync') == null) await _backupLocalFile();
        final ops = await local.query('pending_ops', orderBy: 'id');
        for (final row in ops) {
          final data = jsonDecode(row['data'] as String) as Map<String, Object?>;
          await remote
              .transaction((txn) => _apply(txn, row['kind'] as String, data))
              .timeout(_opTimeout);
          await local.delete('pending_ops', where: 'id = ?', whereArgs: [row['id']]);
        }
        await _copyAll(from: remote, to: local);
      }
      lastSync = DateTime.now();
      await _setMeta('last_sync', lastSync!.toIso8601String());
      lastError = null;
      dataVersion++;
    } catch (e) {
      _goOffline(e);
    } finally {
      syncing = false;
      await _refreshPending();
      notifyListeners();
    }
  }

  static Future<bool> _hasNoBusinessData(Database d) async {
    final r = await d.rawQuery('SELECT (SELECT COUNT(*) FROM projects) + '
        '(SELECT COUNT(*) FROM expenses) + (SELECT COUNT(*) FROM incomes) AS c');
    return ((r.first['c'] as int?) ?? 0) == 0;
  }

  /// Replaces the data tables of [to] with those of [from].
  static Future<void> _copyAll({required Database from, required Database to}) async {
    final data = <String, List<Map<String, Object?>>>{
      for (final t in _tables) t: await from.query(t),
    };
    await to.transaction((txn) async {
      for (final t in _tables) {
        await txn.delete(t);
      }
      final batch = txn.batch();
      for (final t in _tables) {
        for (final row in data[t]!) {
          batch.insert(t, row);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> _backupLocalFile() async {
    final l = _local;
    if (l == null) return;
    try {
      await l.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final stamp = _now().replaceAll(':', '-').split('.').first;
      await File(_localPath).copy('$_localPath.pre-sync-$stamp');
    } catch (_) {
      // Best effort; the share is the source of truth from here on.
    }
  }

  Future<String?> _meta(String key) async {
    final rows = await _local!
        .query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _setMeta(String key, String value) async {
    await _local!.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _loadLastSync() async {
    final v = await _meta('last_sync');
    lastSync = v == null ? null : DateTime.tryParse(v);
  }

  Future<void> _refreshPending() async {
    final l = _local;
    if (l == null) return;
    final r = await l.rawQuery('SELECT COUNT(*) AS c FROM pending_ops');
    pendingCount = (r.first['c'] as int?) ?? 0;
  }

  // ------------------------------------------------------- read / write core

  Future<T> _read<T>(Future<T> Function(Database d) f) async {
    final r = _remote;
    if (r != null) {
      try {
        return await f(r).timeout(_opTimeout);
      } catch (e) {
        _goOffline(e);
      }
    }
    return f(await _ensureLocal());
  }

  static bool _isConstraint(Object e) =>
      e is DatabaseException && e.toString().contains('UNIQUE');

  Future<void> _mutate(String kind, Map<String, Object?> data) {
    return _locked(() async {
      final local = await _ensureLocal();
      await local.transaction((txn) => _apply(txn, kind, data));

      final remote = _remote;
      if (remote != null) {
        try {
          await remote
              .transaction((txn) => _apply(txn, kind, data))
              .timeout(_opTimeout);
          return;
        } catch (e) {
          if (_isConstraint(e)) return;
          _goOffline(e);
        }
      }
      await local.insert('pending_ops', {
        'kind': kind,
        'data': jsonEncode(data),
        'created_at': _now(),
      });
      await _refreshPending();
      notifyListeners();
    });
  }

  /// Applies one operation. Runs against both databases, so it must only use
  /// stable keys and must be safe to run twice.
  static Future<void> _apply(
      DatabaseExecutor x, String kind, Map<String, Object?> d) async {
    Future<Map<String, Object?>?> byUid(String table) async {
      final rows = await x.query(table,
          where: 'uid = ?', whereArgs: [d['uid']], limit: 1);
      return rows.isEmpty ? null : rows.first;
    }

    switch (kind) {
      case 'project_add':
        await x.rawInsert(
          'INSERT OR IGNORE INTO projects (name, budget_percentage, total_income, created_at) '
          'VALUES (?, 100.0, 0, ?)',
          [d['name'], d['created_at']],
        );
      case 'setting_set':
        await x.insert('settings', {'key': d['key'], 'value': d['value']},
            conflictAlgorithm: ConflictAlgorithm.replace);

      case 'user_add':
        await x.rawInsert(
          'INSERT OR IGNORE INTO users (username, password_hash, full_name, role, created_at) '
          'VALUES (?, ?, ?, ?, ?)',
          [d['username'], d['password_hash'], d['full_name'], d['role'], d['created_at']],
        );
      case 'user_role':
        await x.update('users', {'role': d['role']},
            where: 'username = ?', whereArgs: [d['username']]);
      case 'user_password':
        await x.update('users', {'password_hash': d['password_hash']},
            where: 'username = ?', whereArgs: [d['username']]);
      case 'user_delete':
        await x.delete('users', where: 'username = ?', whereArgs: [d['username']]);
      case 'user_rename':
        await x.update('users', {'full_name': d['new']},
            where: 'username = ?', whereArgs: [d['username']]);
        if (d['old'] != d['new']) {
          for (final (table, col) in const [
            ('expenses', 'approved_by'),
            ('expenses', 'created_by'),
            ('incomes', 'created_by'),
          ]) {
            await x.update(table, {col: d['new']},
                where: '$col = ?', whereArgs: [d['old']]);
          }
        }

      case 'expense_add':
        if (await byUid('expenses') != null) return;
        await x.insert('expenses', {
          'uid': d['uid'],
          'project_name': d['project_name'],
          'date': d['date'],
          'amount': d['amount'],
          'payee': d['payee'],
          'description': d['description'],
          'is_approved': 0,
          'created_by': d['created_by'],
          'created_at': d['created_at'],
        });
      case 'expense_update':
        await x.update(
          'expenses',
          {
            'project_name': d['project_name'],
            'date': d['date'],
            'amount': d['amount'],
            'payee': d['payee'],
            'description': d['description'],
          },
          where: 'uid = ?',
          whereArgs: [d['uid']],
        );
      case 'expense_approval':
        final approved = d['approved'] == 1;
        await x.update(
          'expenses',
          {
            'is_approved': approved ? 1 : 0,
            'approved_by': approved ? d['by'] : null,
            'approved_at': approved ? d['at'] : null,
          },
          where: 'uid = ?',
          whereArgs: [d['uid']],
        );
      case 'expense_delete':
        await x.delete('expenses', where: 'uid = ?', whereArgs: [d['uid']]);

      case 'income_add':
        if (await byUid('incomes') != null) return;
        await x.insert('incomes', {
          'uid': d['uid'],
          'project_name': d['project_name'],
          'amount': d['amount'],
          'date': d['date'],
          'created_by': d['created_by'],
          'created_at': d['created_at'],
        });
        await x.rawUpdate(
          'UPDATE projects SET total_income = total_income + ? WHERE name = ?',
          [d['amount'], d['project_name']],
        );
      case 'income_update':
        final row = await byUid('incomes');
        if (row == null) return;
        final old = (row['amount'] as num).toDouble();
        final amount = (d['amount'] as num).toDouble();
        await x.update('incomes', {'amount': amount},
            where: 'uid = ?', whereArgs: [d['uid']]);
        await x.rawUpdate(
          'UPDATE projects SET total_income = total_income + ? WHERE name = ?',
          [amount - old, row['project_name']],
        );
      case 'income_delete':
        final row = await byUid('incomes');
        if (row == null) return;
        await x.delete('incomes', where: 'uid = ?', whereArgs: [d['uid']]);
        await x.rawUpdate(
          'UPDATE projects SET total_income = total_income - ? WHERE name = ?',
          [row['amount'], row['project_name']],
        );

      default:
        throw StateError('unknown operation $kind');
    }
  }

  // ---------------------------------------------------------------- users

  Future<int> userCount() => _read((d) async {
        final r = await d.rawQuery('SELECT COUNT(*) AS c FROM users');
        return (r.first['c'] as int?) ?? 0;
      });

  Future<List<AppUser>> getUsers() => _read((d) async {
        final rows = await d.query('users', orderBy: 'id');
        return rows.map(AppUser.fromMap).toList();
      });

  Future<Map<String, Object?>?> getUserRowByUsername(String username) =>
      _read((d) async {
        final rows = await d.query('users',
            where: 'username = ?', whereArgs: [username], limit: 1);
        return rows.isEmpty ? null : rows.first;
      });

  Future<void> insertUser({
    required String username,
    required String passwordHash,
    required String fullName,
    required String role,
  }) =>
      _mutate('user_add', {
        'username': username,
        'password_hash': passwordHash,
        'full_name': fullName,
        'role': role,
        'created_at': _now(),
      });

  Future<void> updateUserRole(String username, String role) =>
      _mutate('user_role', {'username': username, 'role': role});

  Future<void> updateUserPassword(String username, String passwordHash) =>
      _mutate('user_password', {'username': username, 'password_hash': passwordHash});

  /// Renames a user and carries the new name into the creator/approver stamps
  /// that were written with the old one.
  Future<void> updateUserFullName(String username, String oldName, String newName) =>
      _mutate('user_rename', {'username': username, 'old': oldName, 'new': newName});

  Future<int> adminCount() => _read((d) async {
        final r = await d
            .rawQuery("SELECT COUNT(*) AS c FROM users WHERE role = 'admin'");
        return (r.first['c'] as int?) ?? 0;
      });

  Future<void> deleteUser(String username) =>
      _mutate('user_delete', {'username': username});

  // ------------------------------------------------------------- projects

  Future<List<Project>> getProjects() => _read((d) async {
        final rows = await d.query('projects', orderBy: 'name COLLATE NOCASE');
        return rows.map(Project.fromMap).toList();
      });

  Future<List<ProjectSummary>> getProjectSummaries() async {
    final pct = await getBudgetPercentage();
    return _read((d) async {
      final rows = await d.rawQuery('''
SELECT p.*,
  COALESCE((SELECT SUM(e.amount) FROM expenses e
            WHERE e.project_name = p.name), 0) AS total_expenses,
  COALESCE((SELECT SUM(e.amount) FROM expenses e
            WHERE e.project_name = p.name AND e.is_approved = 1), 0)
            AS approved_expenses
FROM projects p
ORDER BY p.name COLLATE NOCASE
''');
      return rows.map((r) => ProjectSummary.fromMap(r, pct)).toList();
    });
  }

  Future<ProjectSummary?> getProjectSummary(String name) async {
    final all = await getProjectSummaries();
    for (final s in all) {
      if (s.name == name) return s;
    }
    return null;
  }

  Future<void> insertProject(String name) =>
      _mutate('project_add', {'name': name, 'created_at': _now()});

  static const _budgetKey = 'budget_percentage';

  /// The single budget percentage applied to every project (default 100).
  Future<double> getBudgetPercentage() => _read((d) async {
        final rows = await d.query('settings',
            where: 'key = ?', whereArgs: [_budgetKey], limit: 1);
        if (rows.isEmpty) return 100.0;
        return double.tryParse(rows.first['value'] as String) ?? 100.0;
      });

  Future<void> setBudgetPercentage(double pct) =>
      _mutate('setting_set', {'key': _budgetKey, 'value': pct.toString()});

  /// Sums per Jalali month ("yyyy/MM") across all projects, for the dashboard
  /// trend chart. Returns (incomeByMonth, expenseByMonth).
  Future<(Map<String, double>, Map<String, double>)> getMonthlyTotals() =>
      _read((d) async {
        Future<Map<String, double>> sums(String table) async {
          final rows = await d.rawQuery(
              'SELECT substr(date, 1, 7) AS m, SUM(amount) AS s FROM $table GROUP BY m');
          return {
            for (final r in rows)
              if (r['m'] != null) r['m'] as String: (r['s'] as num).toDouble(),
          };
        }

        return (await sums('incomes'), await sums('expenses'));
      });

  // ------------------------------------------------------------- expenses

  /// Every expense / income across all projects, newest first.
  Future<List<Expense>> getAllExpenses() => _read((d) async {
        final rows = await d.query('expenses', orderBy: 'date DESC, id DESC');
        return rows.map(Expense.fromMap).toList();
      });

  Future<List<Income>> getAllIncomes() => _read((d) async {
        final rows = await d.query('incomes', orderBy: 'date DESC, id DESC');
        return rows.map(Income.fromMap).toList();
      });

  Future<List<Expense>> getExpenses(String projectName) => _read((d) async {
        final rows = await d.query('expenses',
            where: 'project_name = ?',
            whereArgs: [projectName],
            orderBy: 'date DESC, id DESC');
        return rows.map(Expense.fromMap).toList();
      });

  Future<void> insertExpense(Expense e, String createdBy) =>
      _mutate('expense_add', {
        'uid': newUid(),
        'project_name': e.projectName,
        'date': e.date,
        'amount': e.amount,
        'payee': e.payee,
        'description': e.description,
        'created_by': createdBy,
        'created_at': _now(),
      });

  Future<void> updateExpense(Expense e) => _mutate('expense_update', {
        'uid': e.uid,
        'project_name': e.projectName,
        'date': e.date,
        'amount': e.amount,
        'payee': e.payee,
        'description': e.description,
      });

  /// Ticks or unticks an expense. The approval date (Jalali) is stamped now.
  Future<void> setExpenseApproval(String uid, bool approved, String by,
          {String? at}) =>
      _mutate('expense_approval', {
        'uid': uid,
        'approved': approved ? 1 : 0,
        'by': by,
        'at': approved ? (at ?? todayJalali()) : null,
      });

  Future<void> deleteExpense(String uid) => _mutate('expense_delete', {'uid': uid});

  // -------------------------------------------------------------- incomes

  Future<List<Income>> getIncomes(String projectName) => _read((d) async {
        final rows = await d.query('incomes',
            where: 'project_name = ?',
            whereArgs: [projectName],
            orderBy: 'date DESC, id DESC');
        return rows.map(Income.fromMap).toList();
      });

  /// Inserts an income row and additively bumps projects.total_income.
  Future<void> addIncome(Income i, String createdBy) => _mutate('income_add', {
        'uid': newUid(),
        'project_name': i.projectName,
        'amount': i.amount,
        'date': i.date,
        'created_by': createdBy,
        'created_at': _now(),
      });

  Future<void> updateIncomeAmount(String uid, double newAmount) =>
      _mutate('income_update', {'uid': uid, 'amount': newAmount});

  Future<void> deleteIncome(String uid) => _mutate('income_delete', {'uid': uid});
}
