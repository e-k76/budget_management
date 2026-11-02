import 'package:budget_management/models/models.dart';
import 'package:budget_management/services/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectSummary summary(String name, {required double income, required double total, required double approved}) =>
    ProjectSummary(
      project: Project(id: 1, name: name, budgetPercentage: 100, totalIncome: income),
      totalExpenses: total,
      approvedExpenses: approved,
      budgetPercentage: 50,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final projects = [
    summary('Alpha', income: 1000, total: 500, approved: 300),
    summary('Beta', income: 2000, total: 100, approved: 100),
  ];
  final expenses = [
    const Expense(projectName: 'Alpha', date: '1405/01/05', amount: 300, payee: 'A', description: 'x', isApproved: true, approvedBy: 'Ali', approvedAt: '1405/01/06'),
    const Expense(projectName: 'Alpha', date: '1405/01/07', amount: 200, payee: 'B', description: 'y'),
  ];
  final incomes = [const Income(projectName: 'Alpha', amount: 1000, date: '1405/01/01', createdBy: 'a')];

  test('dashboard «هزینه کرد کلی» counts only approved expenses', () {
    final t = ReportService.dashboardTable(projects);
    final col = t.headers.indexOf('هزینه کرد کلی');
    expect(t.rows[0][col], '300'); // not 500
    expect(t.rows[1][col], '100');
    expect(t.footers.single[col], '400'); // not 600
    // مانده هزینه = still unapproved; تراز = budget − approved
    expect(t.rows[0][t.headers.indexOf('مانده هزینه')], '200');
    expect(t.rows[0][t.headers.indexOf('تراز کلی')], '200'); // 1000*50% − 300
  });

  test('expense list shows all rows with status and approved/unapproved totals', () {
    final t = ReportService.expensesTable(expenses, withProject: true);
    expect(t.rows.length, 2);
    final status = t.headers.indexOf('وضعیت تایید');
    expect(t.rows.map((r) => r[status]), ['تاییدشده', 'تاییدنشده']);
    final amount = t.headers.indexOf('مبلغ');
    expect(t.footers[0][amount], '500'); // all
    expect(t.footers[1][amount], '300'); // approved
    expect(t.footers[2][amount], '200'); // unapproved
    for (final r in [...t.rows, ...t.footers]) {
      expect(r.length, t.headers.length);
    }
  });

  test('income list totals', () {
    final t = ReportService.incomesTable(incomes, withProject: true);
    expect(t.footers.single[t.headers.indexOf('مبلغ')], '1,000');
    expect(t.footers.single.length, t.headers.length);
  });

  test('every report builds a PDF', () async {
    final bytes = [
      await ReportService.buildDashboardPdf(projects, budgetPercentage: 50, printedBy: 'x'),
      await ReportService.buildProjectPdf(projects.first,
          expenses: expenses, incomes: incomes, filterNote: 'فیلتر: وضعیت تایید: تاییدشده', printedBy: 'x'),
      await ReportService.buildExpensesPdf(expenses, filterNote: '', printedBy: 'x'),
      await ReportService.buildIncomesPdf(incomes, filterNote: '', printedBy: 'x'),
      // empty lists must not break the layout either
      await ReportService.buildExpensesPdf(const [], filterNote: '', printedBy: 'x'),
    ];
    for (final b in bytes) {
      expect(String.fromCharCodes(b.take(4)), '%PDF');
    }
  });

  test('long reports (many rows) split across pages instead of failing', () async {
    final many = [for (var i = 0; i < 60; i++) summary('پروژه $i', income: 1e9 + i, total: 5e8, approved: 3e8)];
    final dash = await ReportService.buildDashboardPdf(many, budgetPercentage: 100, printedBy: 'x')
        .timeout(const Duration(seconds: 60));
    expect(String.fromCharCodes(dash.take(4)), '%PDF');
    final ex = [
      for (var i = 0; i < 400; i++)
        Expense(projectName: 'پروژه ${i % 9}', date: '1405/08/${(i % 28 + 1).toString().padLeft(2, '0')}', amount: 1e6 + i, payee: 'ایرانسل $i', description: 'توضیحات ' * 12, isApproved: i.isEven)
    ];
    final bytes = await ReportService.buildExpensesPdf(ex, filterNote: '', printedBy: 'x')
        .timeout(const Duration(seconds: 120));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(100000)); // many pages, not a stub
  }, timeout: const Timeout(Duration(minutes: 3)));
}
