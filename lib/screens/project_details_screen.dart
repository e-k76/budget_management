import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/income.dart';
import '../models/project.dart';
import '../providers/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kpi_card.dart';
import '../widgets/ui.dart';
import 'expense_form_screen.dart';
import 'income_form_screen.dart';

class ProjectDetailsScreen extends StatefulWidget {
  const ProjectDetailsScreen({super.key, required this.projectId});
  final int projectId;
  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  List<Expense> _expenses = [];
  List<Income> _incomes = [];
  bool _loaded = false;
  int _seenRevision = -1;

  Project _project(AppState s) => s.projects.firstWhere((p) => p.id == widget.projectId);

  Future<void> _load() async {
    final s = context.read<AppState>();
    final name = _project(s).name;
    final e = await s.expensesOf(name), i = await s.incomesOf(name);
    if (mounted) setState(() { _expenses = e; _incomes = i; _loaded = true; });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _run(Future<void> Function() op) async {
    try {
      await op();
      await _load();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _open(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    await _load();
  }

  Future<void> _editBudget(Project p) async {
    final c = TextEditingController(text: '${p.budgetPercentage}');
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('درصد بودجه پروژه'),
        content: TextField(controller: c, autofocus: true, textDirection: TextDirection.ltr, decoration: const InputDecoration(suffixText: '٪')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(c.text)), child: const Text('ثبت')),
        ],
      ),
    );
    if (v != null && v >= 0 && v <= 100) await _run(() => context.read<AppState>().setBudget(p, v));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = _project(s);
    if (s.revision != _seenRevision) {
      // data changed (here or on another PC): re-query this project's rows
      _seenRevision = s.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _load() : null);
    }
    return Scaffold(
      appBar: AppBar(title: Text('کارتابل پروژه: ${p.name}'), actions: [
        if (s.isAdmin) TextButton.icon(onPressed: () => _editBudget(p), icon: const Icon(Icons.percent), label: Text('بودجه ${Fmt.percent(p.budgetPercentage)}')),
        if (s.canEdit) ...[
          TextButton.icon(onPressed: () => _open(ExpenseFormScreen(projectName: p.name)), icon: const Icon(Icons.request_quote_outlined), label: const Text('درخواست وجه')),
          TextButton.icon(onPressed: () => _open(IncomeFormScreen(projectName: p.name)), icon: const Icon(Icons.add_card), label: const Text('افزایش درآمد')),
        ],
        const SizedBox(width: 8),
      ]),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(24), children: [
              LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 1000 ? 4 : 2;
                final w = (c.maxWidth - (cols - 1) * 16) / cols;
                return Wrap(spacing: 16, runSpacing: 16, children: [
                  SizedBox(width: w, child: KpiCard(title: 'درآمد کلی', value: p.totalIncome, icon: Icons.trending_up, color: kIncome)),
                  SizedBox(width: w, child: KpiCard(title: 'هزینه کرد کلی', value: p.totalExpenses, icon: Icons.trending_down, color: kExpense)),
                  SizedBox(width: w, child: KpiCard(title: 'مانده هزینه', value: p.remaining, icon: Icons.savings_outlined, color: kPrimary)),
                  SizedBox(width: w, child: KpiCard(title: 'تراز (با درصد بودجه)', value: p.balance, icon: Icons.balance, color: Colors.teal)),
                ]);
              }),
              const SizedBox(height: 20),
              _charts(p),
              const SizedBox(height: 20),
              _expensesTable(s),
              const SizedBox(height: 20),
              _incomesTable(s),
            ]),
    );
  }

  // ---------------- charts ----------------
  Widget _charts(Project p) {
    final months = <String>{
      for (final e in _expenses) if (e.date.length >= 7) e.date.substring(0, 7),
      for (final i in _incomes) if (i.date.length >= 7) i.date.substring(0, 7),
    }.toList()..sort();
    double sum<T>(Iterable<T> it, String m, String Function(T) d, double Function(T) a) =>
        it.where((x) => d(x).startsWith(m)).fold(0.0, (t, x) => t + a(x));
    final inc = [for (final m in months) sum<Income>(_incomes, m, (i) => i.date, (i) => i.amount)];
    final exp = [for (final m in months) sum<Expense>(_expenses, m, (e) => e.date, (e) => e.amount)];
    final maxY = [...inc, ...exp, p.totalIncome, p.totalExpenses, 1.0].reduce((a, b) => a > b ? a : b) * 1.15;

    String short(double v) => v >= 1e9 ? '${(v / 1e9).toStringAsFixed(1)}B' : v >= 1e6 ? '${(v / 1e6).toStringAsFixed(1)}M' : v >= 1e3 ? '${(v / 1e3).toStringAsFixed(0)}K' : v.toStringAsFixed(0);
    final axis = AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 52, getTitlesWidget: (v, m) => Text(short(v), style: const TextStyle(fontSize: 10))));
    const none = AxisTitles(sideTitles: SideTitles(showTitles: false));

    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 6), Text(t)]);

    final bar = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('درآمد در برابر هزینه', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: BarChart(BarChartData(
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(drawVerticalLine: false),
              titlesData: FlTitlesData(
                leftTitles: axis, topTitles: none, rightTitles: none,
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 6), child: Text(v == 0 ? 'درآمد' : 'هزینه')))),
              ),
              barGroups: [
                BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: p.totalIncome, color: kIncome, width: 44, borderRadius: BorderRadius.circular(8))]),
                BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: p.totalExpenses, color: kExpense, width: 44, borderRadius: BorderRadius.circular(8))]),
              ],
              barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, r, ri) => BarTooltipItem(Fmt.money(r.toY), const TextStyle(color: Colors.white, fontFamily: 'Vazirmatn')))),
            )),
          ),
        ]),
      ),
    );

    final line = Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Text('روند ماهانه', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), legend(kIncome, 'درآمد'), const SizedBox(width: 12), legend(kExpense, 'هزینه')]),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: months.isEmpty
                ? const Center(child: Text('داده‌ای برای نمایش وجود ندارد'))
                : LineChart(LineChartData(
                    minY: 0, maxY: maxY, minX: 0, maxX: months.length == 1 ? 1 : (months.length - 1).toDouble(),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(drawVerticalLine: false),
                    titlesData: FlTitlesData(
                      leftTitles: axis, topTitles: none, rightTitles: none,
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 1, getTitlesWidget: (v, m) {
                        final i = v.toInt();
                        return (v != i || i >= months.length) ? const SizedBox() : Padding(padding: const EdgeInsets.only(top: 6), child: Text(months[i], style: const TextStyle(fontSize: 10)));
                      })),
                    ),
                    lineBarsData: [
                      for (final (data, color) in [(inc, kIncome), (exp, kExpense)])
                        LineChartBarData(
                          spots: [for (var i = 0; i < months.length; i++) FlSpot(i.toDouble(), data[i])],
                          color: color, isCurved: true, barWidth: 3,
                          belowBarData: BarAreaData(show: true, color: color.withValues(alpha: .08)),
                        ),
                    ],
                  )),
          ),
        ]),
      ),
    );

    return LayoutBuilder(builder: (c, box) => box.maxWidth > 900
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 2, child: bar), const SizedBox(width: 16), Expanded(flex: 3, child: line)])
        : Column(children: [bar, const SizedBox(height: 16), line]));
  }

  // ---------------- tables ----------------
  Widget _section(String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (c, box) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(constraints: BoxConstraints(minWidth: box.maxWidth), child: child))),
          ]),
        ),
      );

  Widget _expensesTable(AppState s) => _section(
        'هزینه‌ها / درخواست‌های وجه',
        _expenses.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('موردی ثبت نشده است'))
            : DataTable(
                columns: const [
                  DataColumn(label: Text('ردیف')), DataColumn(label: Text('تاریخ')), DataColumn(label: Text('مبلغ'), numeric: true),
                  DataColumn(label: Text('درصد')), DataColumn(label: Text('شرح')), DataColumn(label: Text('وضعیت تایید')),
                  DataColumn(label: Text('تاییدکننده')), DataColumn(label: Text('عملیات')),
                ],
                rows: [
                  for (var i = 0; i < _expenses.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(_expenses[i].date)),
                      DataCell(Text(Fmt.number(_expenses[i].amount))),
                      DataCell(Text(Fmt.percent(_expenses[i].percentage))),
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: Text(_expenses[i].description, overflow: TextOverflow.ellipsis))),
                      DataCell(Checkbox(
                        value: _expenses[i].isApproved,
                        onChanged: s.canEdit ? (v) => _run(() => s.setApproval(_expenses[i].id!, v ?? false)) : null,
                      )),
                      DataCell(Text(_expenses[i].approvedBy ?? '—')),
                      DataCell(Row(children: [
                        if (s.canEdit) IconButton(tooltip: 'ویرایش', icon: const Icon(Icons.edit_outlined), onPressed: () => _open(ExpenseFormScreen(expense: _expenses[i]))),
                        if (s.canEdit)
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              final id = _expenses[i].id!; // capture: list may refresh while the dialog is open
                              if (await confirm(context, 'این هزینه حذف شود؟')) await _run(() => s.deleteExpense(id));
                            },
                          ),
                      ])),
                    ]),
                ],
              ),
      );

  Widget _incomesTable(AppState s) => _section(
        'خلاصه درآمدها',
        _incomes.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('درآمدی ثبت نشده است'))
            : DataTable(
                columns: const [
                  DataColumn(label: Text('ردیف')), DataColumn(label: Text('تاریخ')), DataColumn(label: Text('مبلغ'), numeric: true),
                  DataColumn(label: Text('ثبت‌کننده')), DataColumn(label: Text('عملیات')),
                ],
                rows: [
                  for (var i = 0; i < _incomes.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(_incomes[i].date)),
                      DataCell(Text(Fmt.number(_incomes[i].amount))),
                      DataCell(Text(_incomes[i].createdBy ?? '—')),
                      DataCell(Row(children: [
                        if (s.canEdit) IconButton(tooltip: 'ویرایش', icon: const Icon(Icons.edit_outlined), onPressed: () => _open(IncomeFormScreen(income: _incomes[i]))),
                        if (s.isAdmin)
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              if (await confirm(context, 'این درآمد حذف شود؟')) await _run(() => s.deleteIncome(_incomes[i].id!));
                            },
                          ),
                      ])),
                    ]),
                ],
              ),
      );
}
