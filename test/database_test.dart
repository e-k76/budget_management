import 'dart:io';

import 'package:budget_management/models/models.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late DatabaseService db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_test');
    db = DatabaseService.instance
      ..localPathOverride = '${tmp.path}/local/projects.db'
      ..remotePathOverride = '${tmp.path}/remote/projects.db'
      ..remoteEnabled = false
      ..simulateUnreachable = false;
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  group('single database', () {
    test('schema, WAL, seed admin, login', () async {
      final d = await db.db;
      final mode = await d.rawQuery('PRAGMA journal_mode');
      expect(mode.first.values.first.toString().toLowerCase(), 'wal');

      final auth = AuthService(db);
      await auth.seedAdminIfEmpty();
      await auth.seedAdminIfEmpty();
      expect(await db.userCount(), 1);
      expect(await auth.login('admin', 'nope'), isFalse);
      expect(await auth.login('admin', 'admin123'), isTrue);
      expect(auth.currentUser!.isAdmin, isTrue);
    });

    test('income is additive and edits/deletes keep total_income in sync', () async {
      await db.insertProject('Alpha');
      await db.addIncome(
          const Income(projectName: 'Alpha', amount: 1000, date: '1403/01/01'), 'a');
      await db.addIncome(
          const Income(projectName: 'Alpha', amount: 500, date: '1403/01/02'), 'a');
      expect((await db.getProjectSummary('Alpha'))!.income, 1500);

      final rows = await db.getIncomes('Alpha');
      await db.updateIncomeAmount(rows.first.uid!, 2000);
      await db.deleteIncome(rows.last.uid!);
      final remaining = await db.getIncomes('Alpha');
      expect(remaining.length, 1);
      expect((await db.getProjectSummary('Alpha'))!.income, remaining.single.amount);
    });

    test('expenses, approval stamp and summary maths', () async {
      await db.insertProject('Beta');
      await db.addIncome(
          const Income(projectName: 'Beta', amount: 1000, date: '1403/01/01'), 'a');
      await db.setBudgetPercentage(50);
      await db.insertExpense(
          const Expense(projectName: 'Beta', date: '1403/01/05', amount: 200), 'a');
      final e = (await db.getExpenses('Beta')).single;
      expect(e.isApproved, isFalse);
      expect(e.uid, isNotNull);
      await db.setExpenseApproval(e.uid!, true, 'Ali');
      final approved = (await db.getExpenses('Beta')).single;
      expect(approved.isApproved, isTrue);
      expect(approved.approvedBy, 'Ali');

      final s = (await db.getProjectSummary('Beta'))!;
      expect(s.remaining, 800);
      expect(s.balance, 300); // 1000 * 50% - 200
      expect(s.approvedExpenses, 200);
    });

    test('balance counts only approved expenses; approval date is stamped and cleared', () async {
      await db.insertProject('G');
      await db.addIncome(
          const Income(projectName: 'G', amount: 1000, date: '1405/01/01'), 'a');
      await db.setBudgetPercentage(80);
      await db.insertExpense(
          const Expense(projectName: 'G', date: '1405/01/02', amount: 100), 'a');
      await db.insertExpense(
          const Expense(projectName: 'G', date: '1405/01/03', amount: 300), 'a');
      final rows = await db.getExpenses('G');
      final hundred = rows.firstWhere((e) => e.amount == 100);

      await db.setExpenseApproval(hundred.uid!, true, 'Ali', at: '1405/02/10');
      final s = (await db.getProjectSummary('G'))!;
      // 1000 * 80% - approved (100); the unapproved 300 is ignored.
      expect(s.balance, 700);
      expect(s.unapprovedExpenses, 300);
      final ticked = (await db.getExpenses('G')).firstWhere((e) => e.amount == 100);
      expect(ticked.approvedAt, '1405/02/10');

      await db.setExpenseApproval(hundred.uid!, false, 'Ali');
      final unticked = (await db.getExpenses('G')).firstWhere((e) => e.amount == 100);
      expect(unticked.approvedAt, isNull);
      expect(unticked.approvedBy, isNull);
      expect((await db.getProjectSummary('G'))!.balance, 800);
    });

    test('all-expenses / all-incomes span projects, newest first', () async {
      await db.insertProject('P1');
      await db.insertProject('P2');
      await db.insertExpense(
          const Expense(projectName: 'P1', date: '1405/01/01', amount: 1), 'a');
      await db.insertExpense(
          const Expense(projectName: 'P2', date: '1405/02/01', amount: 2), 'a');
      await db.addIncome(
          const Income(projectName: 'P2', amount: 5, date: '1405/03/01'), 'a');
      final e = await db.getAllExpenses();
      expect(e.map((x) => x.projectName), ['P2', 'P1']);
      expect((await db.getAllIncomes()).single.projectName, 'P2');
      final (inc, exp) = await db.getMonthlyTotals();
      expect(inc['1405/03'], 5);
      expect(exp['1405/01'], 1);
    });

    test('renaming a user updates approver/creator stamps', () async {
      await db.insertUser(
          username: 'ali', passwordHash: 'x', fullName: 'Old Name', role: 'manager');
      await db.insertProject('P');
      await db.insertExpense(
          const Expense(projectName: 'P', date: '1405/01/01', amount: 1), 'Old Name');
      final e = (await db.getExpenses('P')).single;
      await db.setExpenseApproval(e.uid!, true, 'Old Name');
      await db.updateUserFullName('ali', 'Old Name', 'علی رضایی');
      final after = (await db.getExpenses('P')).single;
      expect(after.approvedBy, 'علی رضایی');
      expect(after.createdBy, 'علی رضایی');
      expect((await db.getUsers()).single.fullName, 'علی رضایی');
    });

    test('migration adds payee/uid and splits imported "payee — description"', () async {
      // An old-format database: no payee/uid columns, imported row with joined text.
      final path = '${tmp.path}/old/projects.db';
      await Directory('${tmp.path}/old').create(recursive: true);
      final old = await databaseFactoryFfi.openDatabase(path);
      await old.execute('''CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT, project_name TEXT NOT NULL,
        date TEXT NOT NULL, amount REAL NOT NULL, percentage REAL DEFAULT 0,
        description TEXT, is_approved INTEGER DEFAULT 0, approved_by TEXT,
        created_by TEXT, created_at TEXT)''');
      await old.insert('expenses', {
        'project_name': 'P',
        'date': '1405/01/01',
        'amount': 5,
        'description': 'الست — بدهی',
        'created_by': 'Access import'
      });
      await old.insert('expenses', {
        'project_name': 'P',
        'date': '1405/01/02',
        'amount': 6,
        'description': 'free text — with dash',
        'created_by': 'Ali'
      });
      await old.close();

      db.localPathOverride = path;
      await db.close();
      final rows = await db.getExpenses('P');
      final imported = rows.firstWhere((e) => e.amount == 5);
      expect(imported.payee, 'الست');
      expect(imported.description, 'بدهی');
      final manual = rows.firstWhere((e) => e.amount == 6);
      expect(manual.payee, '');
      expect(manual.description, 'free text — with dash');
      expect(rows.map((e) => e.uid).toSet().length, 2); // unique uids assigned
      expect(rows.every((e) => (e.uid ?? '').isNotEmpty), isTrue);
    });

    test('duplicate project name is ignored, not duplicated', () async {
      await db.insertProject('Dup');
      await db.insertProject('Dup');
      expect((await db.getProjects()).length, 1);
    });
  });

  group('local + remote sync', () {
    late String remotePath;

    setUp(() async {
      db.remoteEnabled = true;
      remotePath = '${tmp.path}/remote/projects.db';
    });

    /// Reads the share's file through its own handle, independent of the app.
    Future<T> inRemote<T>(Future<T> Function(Database d) f) async {
      final d = await databaseFactoryFfi.openDatabase(remotePath);
      try {
        return await f(d);
      } finally {
        await d.close();
      }
    }

    Future<int> count(Database d, String table) async =>
        (await d.rawQuery('SELECT COUNT(*) c FROM $table')).first['c'] as int;

    test('offline work is queued, then seeds an empty share and clears the queue', () async {
      await db.init(waitForConnection: true); // share folder does not exist -> offline
      expect(db.online, isFalse);

      await db.insertProject('Alpha');
      await db.insertExpense(
          const Expense(projectName: 'Alpha', date: '1405/01/01', amount: 7, payee: 'X'), 'a');
      expect(db.pendingCount, 2);
      expect((await db.getExpenses('Alpha')).single.amount, 7); // served locally

      await Directory('${tmp.path}/remote').create();
      await db.tick();

      expect(db.online, isTrue);
      expect(db.pendingCount, 0);
      await inRemote((d) async {
        expect(await count(d, 'projects'), 1);
        expect(await count(d, 'expenses'), 1);
      });
    });

    test('while connected, writes land in both databases', () async {
      await Directory('${tmp.path}/remote').create();
      await db.init(waitForConnection: true);
      expect(db.online, isTrue);

      await db.insertProject('Alpha');
      await db.addIncome(
          const Income(projectName: 'Alpha', amount: 50, date: '1405/01/01'), 'a');
      expect(db.pendingCount, 0);

      await inRemote((d) async {
        expect(await count(d, 'projects'), 1);
        expect((await d.query('projects')).single['total_income'], 50);
      });
      // The local file has it too (read it through a separate handle).
      final local = await databaseFactoryFfi.openDatabase('${tmp.path}/local/projects.db');
      expect(await count(local, 'incomes'), 1);
      await local.close();
    });

    test('changes made while disconnected are replayed, and remote changes are pulled', () async {
      await Directory('${tmp.path}/remote').create();
      await db.init(waitForConnection: true);
      await db.insertProject('Alpha');
      await db.insertExpense(
          const Expense(projectName: 'Alpha', date: '1405/01/01', amount: 10), 'a');
      final first = (await db.getExpenses('Alpha')).single;

      // The share goes away.
      db.simulateUnreachable = true;
      await db.tick();
      expect(db.online, isFalse);

      // Offline: add, approve, and add income.
      await db.insertExpense(
          const Expense(projectName: 'Alpha', date: '1405/01/02', amount: 20), 'a');
      await db.setExpenseApproval(first.uid!, true, 'Ali', at: '1405/03/01');
      await db.addIncome(
          const Income(projectName: 'Alpha', amount: 99, date: '1405/01/03'), 'a');
      expect(db.pendingCount, 3);
      expect((await db.getExpenses('Alpha')).length, 2); // visible locally

      // Meanwhile somebody else writes to the share directly.
      await inRemote((d) async {
        await d.insert('expenses', {
          'uid': 'other-user-row',
          'project_name': 'Alpha',
          'date': '1405/01/04',
          'amount': 5,
          'payee': 'Y',
          'description': 'from elsewhere',
        });
      });
      await inRemote((d) async {
        expect(await count(d, 'expenses'), 2); // ours not there yet
        expect((await d.query('expenses', where: 'uid = ?', whereArgs: [first.uid])).single['is_approved'], 0);
      });

      // The share returns.
      db.simulateUnreachable = false;
      await db.tick();
      expect(db.online, isTrue);
      expect(db.pendingCount, 0);

      await inRemote((d) async {
        expect(await count(d, 'expenses'), 3); // 10 + 20 + other's 5
        expect((await d.query('expenses', where: 'uid = ?', whereArgs: [first.uid])).single['is_approved'], 1);
        expect((await d.query('expenses', where: 'uid = ?', whereArgs: [first.uid])).single['approved_at'], '1405/03/01');
        expect((await d.query('projects')).single['total_income'], 99);
      });
      // ...and the other person's row is now visible here as well.
      final all = await db.getExpenses('Alpha');
      expect(all.map((e) => e.amount).toSet(), {10, 20, 5});
    });

    test('replaying twice does not duplicate anything', () async {
      await Directory('${tmp.path}/remote').create();
      await db.init(waitForConnection: true);
      await db.insertProject('Alpha');
      db.simulateUnreachable = true;
      await db.tick();
      await db.addIncome(
          const Income(projectName: 'Alpha', amount: 40, date: '1405/01/01'), 'a');
      final op = (await (await db.db).query('pending_ops')).single;

      db.simulateUnreachable = false;
      await db.tick();
      // Simulate a replay that overlapped a write that had actually succeeded.
      final remote = db.remoteHandle!;
      await remote.insert('pending_ops', {'kind': op['kind'], 'data': op['data']});
      await (await db.db).insert('pending_ops', {'kind': op['kind'], 'data': op['data']});
      await db.syncNow(); // nothing pending is replayed twice
      await db.close();
      await inRemote((d) async {
        expect(await count(d, 'incomes'), 1);
        expect((await d.query('projects')).single['total_income'], 40);
      });
    });
  });
}
