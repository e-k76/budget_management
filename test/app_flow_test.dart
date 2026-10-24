import 'dart:io';

import 'package:budget_management/models/expense.dart';
import 'package:budget_management/providers/app_state.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:budget_management/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('bm_test');
    DatabaseService.pathOverride = '${tmp.path}/projects.db';
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('login, projects, income & expense flow, RBAC', () async {
    final s = AppState();
    expect(await s.login('admin', 'wrong'), isFalse);
    expect(await s.login('admin', 'admin123'), isTrue);

    await s.addProject('پروژه الف');
    expect(() => s.addProject('پروژه الف'), throwsA(anything)); // UNIQUE
    await s.addIncome('پروژه الف', 1000000, '1404/01/10');
    await s.addIncome('پروژه الف', 500000, '1404/02/10');
    expect(s.projects.single.totalIncome, 1500000);

    final inc = (await s.incomesOf('پروژه الف')).first;
    await s.updateIncome(inc.id!, 300000, inc.date);
    expect(s.projects.single.totalIncome, 1300000);
    await s.deleteIncome(inc.id!);
    expect(s.projects.single.totalIncome, 1000000);

    await s.saveExpense(const Expense(projectName: 'پروژه الف', date: '1404/01/12', amount: 250000, percentage: 10, description: 'x'));
    final e = (await s.expensesOf('پروژه الف')).single;
    expect(e.isApproved, isFalse);
    await s.setApproval(e.id!, true);
    final e2 = (await s.expensesOf('پروژه الف')).single;
    expect(e2.isApproved, isTrue);
    expect(e2.approvedBy, 'مدیر سیستم');
    expect(s.projects.single.remaining, 750000);

    // viewer cannot write
    await s.createUser('v', 'secret1', 'Viewer', 'viewer');
    s.logout();
    expect(await s.login('v', 'secret1'), isTrue);
    expect(() => s.addIncome('پروژه الف', 1, '1404/01/01'), throwsStateError);
    expect(() => s.deleteExpense(e.id!), throwsStateError);
  });

  test('PDF report builds', () async {
    final s = AppState();
    await s.login('admin', 'admin123');
    final bytes = await ReportService.buildDashboardReport(s.projects, 'tester');
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
