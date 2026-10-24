import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/report_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kpi_card.dart';
import '../widgets/ui.dart';
import 'expense_form_screen.dart';
import 'income_form_screen.dart';
import 'project_details_screen.dart';
import 'scratchpad_screen.dart';
import 'users_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  Future<void> _newProject(BuildContext context) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعریف پروژه جدید'),
        content: SizedBox(width: 360, child: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'نام پروژه'), onSubmitted: (v) => Navigator.pop(context, v))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('ثبت')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<AppState>().addProject(name);
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _print(BuildContext context) async {
    final s = context.read<AppState>();
    try {
      await Printing.layoutPdf(
        name: 'گزارش-پروژه‌ها',
        format: ReportService.format,
        onLayout: (_) => ReportService.buildDashboardReport(s.projects, s.user!.fullName),
      );
    } catch (e) {
      if (context.mounted) toast(context, 'خطا در تولید گزارش: ${errText(e)}', error: true);
    }
  }

  void _push(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد اصلی', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          Center(child: Text('${s.user!.fullName} (${s.user!.roleLabel})')),
          IconButton(tooltip: 'بروزرسانی', icon: const Icon(Icons.refresh), onPressed: s.refresh),
          IconButton(tooltip: 'خروج', icon: const Icon(Icons.logout), onPressed: s.logout),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 1100 ? 4 : (c.maxWidth > 600 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          final cards = [
            KpiCard(title: 'کل درآمد', value: s.totalIncome, icon: Icons.trending_up, color: kIncome),
            KpiCard(title: 'کل هزینه‌ها', value: s.totalExpenses, icon: Icons.trending_down, color: kExpense),
            KpiCard(title: 'مانده بودجه', value: s.remaining, icon: Icons.savings_outlined, color: kPrimary),
            KpiCard(title: 'تراز خالص', value: s.netBalance, icon: Icons.balance, color: Colors.teal),
          ];
          return Wrap(spacing: 16, runSpacing: 16, children: [for (final k in cards) SizedBox(width: w, child: k)]);
        }),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, children: [
          if (s.isAdmin) FilledButton.icon(onPressed: () => _newProject(context), icon: const Icon(Icons.create_new_folder_outlined), label: const Text('تعریف پروژه جدید')),
          if (s.canEdit) FilledButton.tonalIcon(onPressed: () => _push(context, const ExpenseFormScreen()), icon: const Icon(Icons.request_quote_outlined), label: const Text('افزودن درخواست وجه')),
          if (s.canEdit) FilledButton.tonalIcon(onPressed: () => _push(context, const IncomeFormScreen()), icon: const Icon(Icons.add_card), label: const Text('افزایش درآمد')),
          OutlinedButton.icon(onPressed: () => _print(context), icon: const Icon(Icons.print_outlined), label: const Text('پرینت / خروجی چاپی')),
          OutlinedButton.icon(onPressed: () => _push(context, const ScratchpadScreen()), icon: const Icon(Icons.calculate_outlined), label: const Text('محیط موقت محاسبات')),
          if (s.isAdmin) OutlinedButton.icon(onPressed: () => _push(context, const UsersScreen()), icon: const Icon(Icons.manage_accounts_outlined), label: const Text('مدیریت کاربران')),
        ]),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth - 24),
                  child: s.projects.isEmpty
                      ? const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('هنوز پروژه‌ای تعریف نشده است')))
                      : DataTable(
                          columns: const [
                            DataColumn(label: Text('ردیف')),
                            DataColumn(label: Text('نام پروژه')),
                            DataColumn(label: Text('درآمد کلی'), numeric: true),
                            DataColumn(label: Text('هزینه کرد کلی'), numeric: true),
                            DataColumn(label: Text('مانده هزینه'), numeric: true),
                            DataColumn(label: Text('تراز کلی با احتساب درصد بودجه'), numeric: true),
                            DataColumn(label: Text('عملیات')),
                          ],
                          rows: [
                            for (var i = 0; i < s.projects.length; i++)
                              DataRow(cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(s.projects[i].name, style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(Fmt.number(s.projects[i].totalIncome))),
                                DataCell(Text(Fmt.number(s.projects[i].totalExpenses))),
                                DataCell(Text(Fmt.number(s.projects[i].remaining))),
                                DataCell(Text('${Fmt.number(s.projects[i].balance)}  (${Fmt.percent(s.projects[i].budgetPercentage)})',
                                    style: TextStyle(color: s.projects[i].balance < 0 ? Colors.red.shade700 : kIncome, fontWeight: FontWeight.bold))),
                                DataCell(TextButton.icon(
                                  onPressed: () => _push(context, ProjectDetailsScreen(projectId: s.projects[i].id)),
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('ورود به کارتابل'),
                                )),
                              ]),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
