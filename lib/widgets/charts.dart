import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/models.dart';
import 'ui_helpers.dart';

/// Persian short form for axis labels (amounts are in rial).
String compactNumber(double v) {
  final a = v.abs();
  String trim(double x, int digits) {
    final s = x.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  if (a >= 1e9) return '${trim(v / 1e9, 1)} میلیارد';
  if (a >= 1e6) return '${trim(v / 1e6, 1)} میلیون';
  if (a >= 1e3) return '${trim(v / 1e3, 0)} هزار';
  return trim(v, 0);
}

String _short(String s, [int max = 11]) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

const List<Color> _palette = [
  Color(0xFF3949AB),
  Color(0xFF2E9E6B),
  Color(0xFFF5A524),
  Color(0xFFE5484D),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFF64748B), // "others"
];

/// Card with a title and a fixed-height chart area.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.child, this.height = 300});

  final String title;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      child: SizedBox(height: height, child: child),
    );
  }
}

/// Lays chart cards out in one or two columns depending on width.
class ChartGrid extends StatelessWidget {
  const ChartGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 2 : 1;
      const gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in children) SizedBox(width: w, child: k)],
      );
    });
  }
}

Widget chartEmpty(BuildContext context, [String text = 'داده‌ای برای نمایش وجود ندارد']) =>
    Center(child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)));

class ChartLegend extends StatelessWidget {
  const ChartLegend(this.items, {super.key});
  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 4,
      children: [
        for (final i in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: i.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(i.$1, style: const TextStyle(fontSize: 12)),
          ]),
      ],
    );
  }
}

// ------------------------------------------------------------------ pies

class _PieWithLegend extends StatelessWidget {
  const _PieWithLegend({required this.parts});

  /// (label, value, color); zero values are skipped.
  final List<(String, double, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$2 > 0).toList();
    final total = shown.fold<double>(0, (a, p) => a + p.$2);
    if (total <= 0) return chartEmpty(context);
    return Row(
      children: [
        Expanded(
          child: PieChart(PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 38,
            sections: [
              for (final p in shown)
                PieChartSectionData(
                  value: p.$2,
                  color: p.$3,
                  radius: 60,
                  title: '${(p.$2 / total * 100).toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
            ],
          )),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 190,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final p in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: p.$3, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${_short(p.$1, 16)}  ·  ${compactNumber(p.$2)}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Approved / pending expenses and what is left of the income (one project).
class ApprovalPie extends StatelessWidget {
  const ApprovalPie(this.s, {super.key});
  final ProjectSummary s;

  @override
  Widget build(BuildContext context) {
    return _PieWithLegend(parts: [
      ('هزینه تاییدشده', s.approvedExpenses, AppTheme.expense),
      ('هزینه تاییدنشده', math.max(0.0, s.totalExpenses - s.approvedExpenses),
          AppTheme.pending),
      ('مانده درآمد', math.max(0.0, s.income - s.totalExpenses), AppTheme.income),
    ]);
  }
}

/// Each project's share of the total expenses (top 6 + others).
class ExpenseSharePie extends StatelessWidget {
  const ExpenseSharePie(this.summaries, {super.key});
  final List<ProjectSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final sorted = [...summaries.where((s) => s.totalExpenses > 0)]
      ..sort((a, b) => b.totalExpenses.compareTo(a.totalExpenses));
    final top = sorted.take(6).toList();
    final others = sorted.skip(6).fold<double>(0, (a, s) => a + s.totalExpenses);
    return _PieWithLegend(parts: [
      for (var i = 0; i < top.length; i++)
        (top[i].name, top[i].totalExpenses, _palette[i]),
      if (others > 0) ('سایر پروژه‌ها', others, _palette.last),
    ]);
  }
}

// ------------------------------------------------------------------ bars

Widget _barChart(
  BuildContext context, {
  required List<String> labels,
  required List<BarChartGroupData> groups,
  required double maxY,
  required String Function(int group) tooltip,
  required List<(String, Color)> legend,
}) {
  return Column(
    children: [
      Expanded(
        child: BarChart(BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: groups,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                tooltip(group.x),
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppConfig.fontFamily),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 78,
                getTitlesWidget: (v, meta) {
                  if (v == meta.max) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(compactNumber(v),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(_short(labels[i]),
                        style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
        )),
      ),
      const SizedBox(height: 8),
      ChartLegend(legend),
    ],
  );
}

BarChartRodData _rod(double v, Color c, {double width = 12}) => BarChartRodData(
      toY: v,
      color: c,
      width: width,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );

BarChartRodData _stackRod(double approved, double pending, {double width = 18}) =>
    BarChartRodData(
      toY: approved + pending,
      width: width,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      rodStackItems: [
        BarChartRodStackItem(0, approved, AppTheme.expense),
        BarChartRodStackItem(approved, approved + pending, AppTheme.pending),
      ],
    );

const _approvalLegend = [
  ('تاییدشده', AppTheme.expense),
  ('تاییدنشده', AppTheme.pending),
];

/// Income vs expenses for the biggest projects.
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars(this.summaries, {super.key});
  final List<ProjectSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final top = [...summaries.where((s) => s.income > 0 || s.totalExpenses > 0)]
      ..sort((a, b) => (b.income + b.totalExpenses).compareTo(a.income + a.totalExpenses));
    final list = top.take(8).toList();
    if (list.isEmpty) return chartEmpty(context);
    final maxY = list.fold<double>(0, (m, s) => math.max(m, math.max(s.income, s.totalExpenses)));
    return _barChart(
      context,
      labels: [for (final s in list) s.name],
      maxY: maxY,
      groups: [
        for (var i = 0; i < list.length; i++)
          BarChartGroupData(x: i, barsSpace: 4, barRods: [
            _rod(list[i].income, AppTheme.income),
            _rod(list[i].totalExpenses, AppTheme.expense),
          ]),
      ],
      tooltip: (g) =>
          '${list[g].name}\nدرآمد: ${formatNumberPlain(list[g].income)}\nهزینه: ${formatNumberPlain(list[g].totalExpenses)}',
      legend: const [('درآمد', AppTheme.income), ('هزینه', AppTheme.expense)],
    );
  }
}

/// Approved vs unapproved expenses per project (stacked).
class ApprovalStackBars extends StatelessWidget {
  const ApprovalStackBars(this.summaries, {super.key});
  final List<ProjectSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final top = [...summaries.where((s) => s.totalExpenses > 0)]
      ..sort((a, b) => b.totalExpenses.compareTo(a.totalExpenses));
    final list = top.take(8).toList();
    if (list.isEmpty) return chartEmpty(context);
    return _barChart(
      context,
      labels: [for (final s in list) s.name],
      maxY: list.first.totalExpenses,
      groups: [
        for (var i = 0; i < list.length; i++)
          BarChartGroupData(x: i, barRods: [
            _stackRod(list[i].approvedExpenses,
                math.max(0.0, list[i].totalExpenses - list[i].approvedExpenses)),
          ]),
      ],
      tooltip: (g) =>
          '${list[g].name}\nتاییدشده: ${formatNumberPlain(list[g].approvedExpenses)}\nتاییدنشده: ${formatNumberPlain(list[g].totalExpenses - list[g].approvedExpenses)}',
      legend: _approvalLegend,
    );
  }
}

/// Approved vs unapproved expenses per month (one project).
class MonthlyApprovalBars extends StatelessWidget {
  const MonthlyApprovalBars(this.expenses, {super.key});
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final approved = <String, double>{};
    final pending = <String, double>{};
    for (final e in expenses) {
      (e.isApproved ? approved : pending)
          .update(monthKey(e.date), (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    var months = {...approved.keys, ...pending.keys}.toList()..sort();
    if (months.isEmpty) return chartEmpty(context);
    if (months.length > 12) months = months.sublist(months.length - 12);
    double a(String m) => approved[m] ?? 0;
    double p(String m) => pending[m] ?? 0;
    return _barChart(
      context,
      labels: [for (final m in months) monthLabel(m)],
      maxY: months.fold<double>(0, (mx, m) => math.max(mx, a(m) + p(m))),
      groups: [
        for (var i = 0; i < months.length; i++)
          BarChartGroupData(x: i, barRods: [_stackRod(a(months[i]), p(months[i]))]),
      ],
      tooltip: (g) =>
          '${monthLabel(months[g])}\nتاییدشده: ${formatNumberPlain(a(months[g]))}\nتاییدنشده: ${formatNumberPlain(p(months[g]))}',
      legend: _approvalLegend,
    );
  }
}

/// Biggest payees ("در وجه") by total amount.
class TopPayeesBars extends StatelessWidget {
  const TopPayeesBars(this.expenses, {super.key});
  final List<Expense> expenses;

  @override
  Widget build(BuildContext context) {
    final sums = <String, double>{};
    for (final e in expenses) {
      final name = e.payee.isEmpty ? 'نامشخص' : e.payee;
      sums.update(name, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final top = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final list = top.take(8).toList();
    if (list.isEmpty) return chartEmpty(context);
    return _barChart(
      context,
      labels: [for (final e in list) e.key],
      maxY: list.first.value,
      groups: [
        for (var i = 0; i < list.length; i++)
          BarChartGroupData(x: i, barRods: [_rod(list[i].value, AppTheme.seed, width: 18)]),
      ],
      tooltip: (g) => '${list[g].key}\n${formatNumberPlain(list[g].value)}',
      legend: const [('مجموع مبلغ به تفکیک دریافت‌کننده', AppTheme.seed)],
    );
  }
}

// ------------------------------------------------------------- line chart

/// Monthly income vs expense trend. Keys are "yyyy/MM".
class MonthlyTrendChart extends StatelessWidget {
  const MonthlyTrendChart({super.key, required this.income, required this.expense});

  final Map<String, double> income;
  final Map<String, double> expense;

  @override
  Widget build(BuildContext context) {
    var months = {...income.keys, ...expense.keys}.toList()..sort();
    if (months.isEmpty) return chartEmpty(context);
    if (months.length > 12) months = months.sublist(months.length - 12);

    LineChartBarData line(Map<String, double> m, Color c) => LineChartBarData(
          spots: [
            for (var i = 0; i < months.length; i++)
              FlSpot(i.toDouble(), m[months[i]] ?? 0),
          ],
          isCurved: true,
          preventCurveOverShooting: true,
          color: c,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, color: c.withValues(alpha: 0.08)),
        );

    final maxY = [...income.values, ...expense.values].fold<double>(0, math.max);
    return Column(
      children: [
        Expanded(
          child: LineChart(LineChartData(
            minY: 0,
            maxY: maxY <= 0 ? 1 : maxY * 1.15,
            gridData: const FlGridData(drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [line(income, AppTheme.income), line(expense, AppTheme.expense)],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      formatNumberPlain(s.y),
                      TextStyle(
                          color: s.bar.color,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppConfig.fontFamily),
                    ),
                ],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 78,
                  getTitlesWidget: (v, meta) {
                    if (v == meta.max) return const SizedBox.shrink();
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(compactNumber(v),
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 30,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (v != i || i < 0 || i >= months.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(monthLabel(months[i]),
                          style: const TextStyle(fontSize: 10)),
                    );
                  },
                ),
              ),
            ),
          )),
        ),
        const SizedBox(height: 8),
        const ChartLegend([('درآمد', AppTheme.income), ('هزینه', AppTheme.expense)]),
      ],
    );
  }
}
