import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/app_user.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/project.dart';
import 'auth_service.dart';

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
      'CREATE INDEX IF NOT EXISTS idx_expenses_project ON expenses(project_name)',
      'CREATE INDEX IF NOT EXISTS idx_incomes_project ON incomes(project_name)',
    ];
    for (final s in ddl) {
      await db.execute(s);
    }
    await _createSyncTriggers(db);
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

  Future<void> addProject(String name) async =>
      (await db).insert('projects', {'name': name.trim(), 'created_at': _now()});

  Future<void> setBudgetPercentage(int id, double pct) async =>
      (await db).update('projects', {'budget_percentage': pct}, where: 'id = ?', whereArgs: [id]);

  // ---------------- Expenses ----------------
  Future<List<Expense>> expenses(String projectName) async => (await (await db).query('expenses',
          where: 'project_name = ?', whereArgs: [projectName], orderBy: 'date DESC, id DESC'))
      .map(Expense.fromMap)
      .toList();

  Future<void> addExpense(Expense e, String user) async => (await db).insert('expenses', {
        'project_name': e.projectName,
        'date': e.date,
        'amount': e.amount,
        'percentage': e.percentage,
        'description': e.description,
        'is_approved': 0,
        'created_by': user,
        'created_at': _now(),
      });

  Future<void> updateExpense(Expense e) async => (await db).update(
        'expenses',
        {
          'date': e.date,
          'amount': e.amount,
          'percentage': e.percentage,
          'description': e.description,
          'project_name': e.projectName,
        },
        where: 'id = ?',
        whereArgs: [e.id],
      );

  Future<void> deleteExpense(int id) async => (await db).delete('expenses', where: 'id = ?', whereArgs: [id]);

  Future<void> setApproval(int id, bool approved, String user) async => (await db).update(
        'expenses',
        {'is_approved': approved ? 1 : 0, 'approved_by': approved ? user : null},
        where: 'id = ?',
        whereArgs: [id],
      );

  // ---------------- Incomes ----------------
  Future<List<Income>> incomes(String projectName) async => (await (await db).query('incomes',
          where: 'project_name = ?', whereArgs: [projectName], orderBy: 'id DESC'))
      .map(Income.fromMap)
      .toList();

  /// total_income = total_income + amount, atomically with the ledger row.
  Future<void> addIncome(String projectName, double amount, String date, String user) async {
    await (await db).transaction((t) async {
      await t.insert('incomes', {
        'project_name': projectName,
        'amount': amount,
        'date': date,
        'created_by': user,
        'created_at': _now(),
      });
      await t.rawUpdate('UPDATE projects SET total_income = total_income + ? WHERE name = ?',
          [amount, projectName]);
    });
  }

  Future<void> updateIncome(int id, double newAmount, String date) async {
    await (await db).transaction((t) async {
      final old = (await t.query('incomes', where: 'id = ?', whereArgs: [id])).first;
      final diff = newAmount - (old['amount'] as num).toDouble();
      await t.update('incomes', {'amount': newAmount, 'date': date}, where: 'id = ?', whereArgs: [id]);
      await t.rawUpdate('UPDATE projects SET total_income = total_income + ? WHERE name = ?',
          [diff, old['project_name']]);
    });
  }

  Future<void> deleteIncome(int id) async {
    await (await db).transaction((t) async {
      final old = (await t.query('incomes', where: 'id = ?', whereArgs: [id])).first;
      await t.delete('incomes', where: 'id = ?', whereArgs: [id]);
      await t.rawUpdate('UPDATE projects SET total_income = total_income - ? WHERE name = ?',
          [old['amount'], old['project_name']]);
    });
  }
}
