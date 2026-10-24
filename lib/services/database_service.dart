import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_user.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/project.dart';
import 'auth_service.dart';
import 'pending_queue.dart';

/// Single SQLite file on the DFS share. Rollback-journal (DELETE) mode + busy_timeout for multi-client access.
/// Every write is a short, atomic transaction.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  static final String dbPath =
      '${Platform.environment['USERPROFILE']}\\Desktop\\project_manage\\projects.db';

  static const String journalMode = 'DELETE';

  /// Tests point the service at a temp file instead of the Desktop share.
  static String? pathOverride;

  Database? _db;

  /// Drop the connection (e.g. after the share went away) so the next call reopens it.
  Future<void> reset() async {
    final d = _db;
    _db = null;
    try {
      await d?.close();
    } catch (_) {}
  }

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = pathOverride ?? dbPath;
    await Directory(File(path).parent.path).create(recursive: true);
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA busy_timeout = 5000;');
          // WAL relies on shared memory (-shm) that does NOT work across PCs on an SMB/DFS
          // share: other PCs can read stale data until a checkpoint. DELETE mode writes
          // straight into the main file under network file locks, so every PC sees a
          // committed change on its next read. Set to 'WAL' only for a local-disk DB.
          await db.rawQuery('PRAGMA journal_mode = $journalMode;');
          await db.rawQuery('PRAGMA synchronous = FULL;');
        },
        onOpen: (db) async {
          await _createSchema(db);
          await _seedAdmin(db);
        },
      ),
    );
  }

  Future<void> _createSchema(Database db) async {
    const ddl = [
      '''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        full_name TEXT NOT NULL,
        role TEXT NOT NULL CHECK(role IN ('admin', 'manager', 'viewer')),
        created_at TEXT
      )''',
      '''CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        budget_percentage REAL DEFAULT 100.0,
        total_income REAL DEFAULT 0,
        created_at TEXT
      )''',
      '''CREATE TABLE IF NOT EXISTS expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_name TEXT NOT NULL,
        date TEXT NOT NULL,
        amount REAL NOT NULL,
        percentage REAL DEFAULT 0,
        description TEXT,
        is_approved INTEGER DEFAULT 0,
        approved_by TEXT,
        created_by TEXT,
        created_at TEXT
      )''',
      // Addition to the spec'd schema: individual income entries so they can be
      // listed/edited/deleted. projects.total_income stays the additive running total.
      '''CREATE TABLE IF NOT EXISTS incomes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_name TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT,
        created_by TEXT,
        created_at TEXT
      )''',
      // Ids of queued writes already applied, so replays after a network drop are idempotent.
      'CREATE TABLE IF NOT EXISTS applied_ops (op_id TEXT PRIMARY KEY, applied_at TEXT)',
      'CREATE INDEX IF NOT EXISTS idx_expenses_project ON expenses(project_name)',
      'CREATE INDEX IF NOT EXISTS idx_incomes_project ON incomes(project_name)',
    ];
    for (final s in ddl) {
      await db.execute(s);
    }
    await _createSyncTriggers(db);
    await db.execute("DELETE FROM applied_ops WHERE applied_at < ?", [DateTime.now().subtract(const Duration(days: 30)).toIso8601String()]);
  }

  /// Live sync: every insert/update/delete on any table bumps `sync_state.version`
  /// (inside the same transaction as the change). Other PCs poll this single row
  /// and reload when it changes.
  Future<void> _createSyncTriggers(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS sync_state (id INTEGER PRIMARY KEY CHECK(id = 1), version INTEGER NOT NULL)');
    await db.execute('INSERT OR IGNORE INTO sync_state (id, version) VALUES (1, 0)');
    for (final t in ['users', 'projects', 'expenses', 'incomes']) {
      for (final op in ['INSERT', 'UPDATE', 'DELETE']) {
        await db.execute('CREATE TRIGGER IF NOT EXISTS trg_sync_${t}_${op.toLowerCase()} '
            'AFTER $op ON $t BEGIN UPDATE sync_state SET version = version + 1 WHERE id = 1; END');
      }
    }
  }

  Future<int> dataVersion() async =>
      (await (await db).rawQuery('SELECT version FROM sync_state WHERE id = 1')).first['version'] as int;

  Future<void> _seedAdmin(Database db) async {
    final c = (await db.rawQuery('SELECT COUNT(*) AS c FROM users')).first['c'] as int;
    if (c == 0) {
      await db.insert('users', {
        'username': 'admin',
        'password_hash': AuthService.hashPassword('admin123'),
        'full_name': 'مدیر سیستم',
        'role': 'admin',
        'created_at': _now(),
      });
    }
  }

  String _now() => DateTime.now().toIso8601String();

  // ---------------- Users ----------------
  Future<Map<String, Object?>?> findUserRow(String username) async {
    final r = await (await db).query('users', where: 'username = ?', whereArgs: [username], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<List<AppUser>> users() async =>
      (await (await db).query('users', orderBy: 'id')).map(AppUser.fromMap).toList();

  Future<void> insertUser(String username, String hash, String fullName, String role) async =>
      (await db).insert('users', {
        'username': username,
        'password_hash': hash,
        'full_name': fullName,
        'role': role,
        'created_at': _now(),
      });

  Future<void> deleteUser(int id) async => (await db).delete('users', where: 'id = ?', whereArgs: [id]);

  // ---------------- Projects ----------------
  Future<List<Project>> projects() async {
    final rows = await (await db).rawQuery('''
      SELECT p.*, COALESCE((SELECT SUM(e.amount) FROM expenses e WHERE e.project_name = p.name), 0) AS total_expenses
      FROM projects p ORDER BY p.id''');
    return rows.map(Project.fromMap).toList();
  }

  Future<void> setBudgetPercentage(int id, double pct) async =>
      (await db).update('projects', {'budget_percentage': pct}, where: 'id = ?', whereArgs: [id]);

  // ---------------- Expenses ----------------
  Future<List<Expense>> expenses(String projectName) async => (await (await db).query('expenses',
          where: 'project_name = ?', whereArgs: [projectName], orderBy: 'date DESC, id DESC'))
      .map(Expense.fromMap)
      .toList();

  // ---------------- Incomes ----------------
  Future<List<Income>> incomes(String projectName) async => (await (await db).query('incomes',
          where: 'project_name = ?', whereArgs: [projectName], orderBy: 'id DESC'))
      .map(Income.fromMap)
      .toList();

  // ---------------- Writes (queued, idempotent) ----------------
  /// Applies one queued write in a single short transaction. If its id was already applied
  /// (e.g. the commit reached the share but the confirmation was lost) it is a no-op.
  Future<void> apply(PendingOp op) async {
    await (await db).transaction((t) async {
      if ((await t.rawQuery('SELECT 1 FROM applied_ops WHERE op_id = ?', [op.id])).isNotEmpty) return;
      await t.insert('applied_ops', {'op_id': op.id, 'applied_at': _now()});
      final d = op.data;
      switch (op.type) {
        case 'addProject':
          await t.insert('projects', {'name': (d['name'] as String).trim(), 'created_at': op.at});
        case 'addExpense':
          await t.insert('expenses', {
            'project_name': d['project'],
            'date': d['date'],
            'amount': d['amount'],
            'percentage': d['percentage'],
            'description': d['description'],
            'is_approved': 0,
            'created_by': d['user'],
            'created_at': op.at,
          });
        case 'updateExpense':
          await t.update(
              'expenses',
              {
                'project_name': d['project'],
                'date': d['date'],
                'amount': d['amount'],
                'percentage': d['percentage'],
                'description': d['description'],
              },
              where: 'id = ?',
              whereArgs: [d['id']]);
        case 'deleteExpense':
          await t.delete('expenses', where: 'id = ?', whereArgs: [d['id']]);
        case 'setApproval':
          final ok = d['approved'] == true;
          await t.update('expenses', {'is_approved': ok ? 1 : 0, 'approved_by': ok ? d['user'] : null},
              where: 'id = ?', whereArgs: [d['id']]);
        case 'addIncome':
          // total_income = total_income + amount, atomically with the ledger row
          await t.insert('incomes', {
            'project_name': d['project'],
            'amount': d['amount'],
            'date': d['date'],
            'created_by': d['user'],
            'created_at': op.at,
          });
          await t.rawUpdate('UPDATE projects SET total_income = total_income + ? WHERE name = ?',
              [d['amount'], d['project']]);
        case 'updateIncome':
          final old = await _incomeRow(t, d['id']);
          final diff = (d['amount'] as num).toDouble() - (old['amount'] as num).toDouble();
          await t.update('incomes', {'amount': d['amount'], 'date': d['date']}, where: 'id = ?', whereArgs: [d['id']]);
          await t.rawUpdate('UPDATE projects SET total_income = total_income + ? WHERE name = ?', [diff, old['project_name']]);
        case 'deleteIncome':
          final old = await _incomeRow(t, d['id']);
          await t.delete('incomes', where: 'id = ?', whereArgs: [d['id']]);
          await t.rawUpdate('UPDATE projects SET total_income = total_income - ? WHERE name = ?', [old['amount'], old['project_name']]);
        default:
          throw StateError('عملیات ناشناخته: ${op.type}');
      }
    });
  }

  Future<Map<String, Object?>> _incomeRow(DatabaseExecutor t, Object? id) async {
    final r = await t.query('incomes', where: 'id = ?', whereArgs: [id]);
    if (r.isEmpty) throw StateError('این درآمد دیگر وجود ندارد (احتمالاً در رایانه دیگری حذف شده است)');
    return r.first;
  }
}
