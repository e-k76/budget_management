import 'package:budget_management/models/models.dart';
import 'package:budget_management/widgets/charts.dart';
import 'package:budget_management/widgets/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectSummary _s(String n, double inc, double exp, double appr) => ProjectSummary(
      project: Project(id: 1, name: n, budgetPercentage: 100, totalIncome: inc),
      totalExpenses: exp,
      approvedExpenses: appr,
      budgetPercentage: 100,
    );

Widget _host(Widget child) => MaterialApp(
      builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
      home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
    );

void main() {
  final summaries = [
    for (var i = 0; i < 12; i++) _s('پروژه $i', 1e9 * (i + 1), 5e8 * (i + 1), 2e8 * (i + 1)),
  ];
  final expenses = [
    for (var i = 0; i < 20; i++)
      Expense(
          projectName: 'p',
          date: '1405/0${1 + i % 6}/10',
          amount: 1e6 * (i + 1),
          description: 'نفر ${i % 5} — شرح',
          isApproved: i.isEven),
  ];

  testWidgets('dashboard charts render', (t) async {
    await t.pumpWidget(_host(SingleChildScrollView(
      child: ChartGrid(children: [
        ChartCard(title: 'a', child: IncomeExpenseBars(summaries)),
        ChartCard(title: 'b', child: ExpenseSharePie(summaries)),
        ChartCard(title: 'c', child: ApprovalStackBars(summaries)),
        ChartCard(
            title: 'd',
            child: const MonthlyTrendChart(
                income: {'1405/01': 5e9, '1405/02': 7e9}, expense: {'1405/01': 3e9})),
      ]),
    )));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('project charts render, including empty data', (t) async {
    await t.pumpWidget(_host(SingleChildScrollView(
      child: ChartGrid(children: [
        ChartCard(title: 'a', child: ApprovalPie(summaries.first)),
        ChartCard(title: 'b', child: MonthlyApprovalBars(expenses)),
        ChartCard(title: 'c', child: TopPayeesBars(expenses)),
        ChartCard(title: 'd', child: const MonthlyApprovalBars([])),
        ChartCard(title: 'e', child: const TopPayeesBars([])),
        ChartCard(title: 'f', child: const MonthlyTrendChart(income: {}, expense: {})),
      ]),
    )));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('pinned table scrolls rows, header and footer stay', (t) async {
    await t.pumpWidget(_host(PinnedTable(
      columns: const [PinnedColumn('ستون الف'), PinnedColumn('ستون ب')],
      rows: [for (var i = 0; i < 60; i++) [Text('r$i'), Text('v$i')]],
      footer: const [Text('جمع'), Text('همه')],
    )));
    expect(find.text('ستون الف'), findsOneWidget);
    expect(find.text('r59'), findsNothing);
    await t.drag(find.byType(ListView), const Offset(0, -3000));
    await t.pump();
    expect(find.text('r59'), findsOneWidget);
    expect(find.text('ستون الف'), findsOneWidget);
    expect(find.text('جمع'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
