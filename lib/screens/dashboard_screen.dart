import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/report_service.dart';
import '../widgets/charts.dart';
import '../widgets/kpi_card.dart';
import '../widgets/status_icons.dart';
import '../widgets/ui_helpers.dart';
import 'entry_dialogs.dart';
import 'project_details_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _search = TextEditingController();
  bool _printing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _print(AppState state, String user) async {
    setState(() => _printing = true);
    try {
      await ReportService.printDashboard(state.summaries,
          budgetPercentage: state.budgetPercentage, printedBy: user);
    } catch (e) {
      if (mounted) showSnack(context, 'خطا در تهیه گزارش: $e', error: true);
    }
    if (mounted) setState(() => _printing = false);
  }

  void _openProject(ProjectSummary s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProjectDetailsScreen(projectName: s.name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = context.watch<AuthService>().currentUser!;
    final q = _search.text.trim();
    final rows =
        state.summaries.where((s) => q.isEmpty || s.name.contains(q)).toList();

    final top = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text('داشبورد اصلی',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton.filledTonal(
            tooltip: 'بروزرسانی',
            onPressed: state.loading ? null : state.refresh,
            icon: state.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _actionBar(context, state, user),
      const SizedBox(height: 16),
      if (state.loadError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(state.loadError!),
            ),
          ),
        ),
      _kpis(state),
      const SizedBox(height: 16),
    ];

    Widget tabs({required double? height}) {
      final card = DefaultTabController(
        length: 2,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const TabBar(tabs: [Tab(text: 'پروژه‌ها'), Tab(text: 'نمودارها')]),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: 280,
                              child: TextField(
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'جستجوی پروژه',
                                  prefixIcon: Icon(Icons.search),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: _table(context, state, rows)),
                      ],
                    ),
                    ListView(
                      padding: const EdgeInsets.all(18),
                      children: [_charts(state)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      return height == null ? card : SizedBox(height: height, child: card);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(builder: (context, c) {
        // Normal case: everything above the tabs stays pinned and only the
        // tab content scrolls. On very short windows fall back to page scroll.
        if (c.maxHeight < 640) {
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [...top, tabs(height: 480)],
          );
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...top, Expanded(child: tabs(height: null))],
          ),
        );
      }),
    );
  }

  Widget _charts(AppState s) {
    return ChartGrid(children: [
      ChartCard(
          title: 'درآمد و هزینه به تفکیک پروژه',
          child: IncomeExpenseBars(s.summaries)),
      ChartCard(
          title: 'سهم هر پروژه از کل هزینه‌ها',
          child: ExpenseSharePie(s.summaries)),
      ChartCard(
          title: 'هزینه تاییدشده و تاییدنشده به تفکیک پروژه',
          child: ApprovalStackBars(s.summaries)),
      ChartCard(
          title: 'روند ماهانه درآمد و هزینه (کل پروژه‌ها)',
          child: MonthlyTrendChart(
              income: s.monthlyIncome, expense: s.monthlyExpense)),
    ]);
  }

  Widget _actionBar(BuildContext context, AppState state, AppUser user) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (user.isAdmin)
          FilledButton.icon(
            onPressed: () => showNewProjectDialog(context),
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('تعریف پروژه جدید'),
          ),
        if (user.canEdit) ...[
          FilledButton.tonalIcon(
            onPressed: () => showExpenseDialog(context),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('افزودن درخواست وجه'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showIncomeDialog(context),
            icon: const Icon(Icons.trending_up_rounded),
            label: const Text('ثبت درآمد'),
          ),
          OutlinedButton.icon(
            onPressed: _printing ? null : () => _print(state, user.fullName),
            icon: const Icon(Icons.print_outlined),
            label: const Text('پرینت / خروجی چاپی'),
          ),
        ],
        // One budget percentage for all projects; admins and managers can change it.
        if (user.canEdit)
          OutlinedButton.icon(
            onPressed: () => showBudgetPercentDialog(context),
            icon: const Icon(Icons.percent_rounded),
            label: Text('درصد بودجه: ${formatPercent(state.budgetPercentage)}'),
          )
        else
          Chip(
            avatar: const Icon(Icons.percent_rounded, size: 18),
            label: Text('درصد بودجه: ${formatPercent(state.budgetPercentage)}'),
          ),
      ],
    );
  }

  Widget _kpis(AppState s) {
    final cards = [
      KpiCard(
          title: 'درآمد کل',
          value: formatMoney(s.totalIncome),
          icon: Icons.south_west_rounded,
          color: AppTheme.income),
      KpiCard(
          title: 'هزینه کرد',
          value: formatMoney(s.totalApproved),
          iconWidget: const DocStatusIcon(approved: true),
          color: DocStatusIcon.approvedColor),
      KpiCard(
          title: 'مانده هزینه',
          value: formatMoney(s.totalUnapproved),
          iconWidget: const DocStatusIcon(approved: false),
          color: DocStatusIcon.unapprovedColor),
      KpiCard(
          title: 'تراز کل',
          value: formatMoney(s.netBalance),
          icon: Icons.balance_rounded,
          color: AppTheme.seed),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 600 ? 2 : 1);
      const gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    });
  }

  Widget _table(BuildContext context, AppState state, List<ProjectSummary> rows) {
    if (state.summaries.isEmpty) {
      return Center(
        child: Text(
          state.loading ? 'در حال بارگذاری...' : 'هنوز پروژه‌ای تعریف نشده است.',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      );
    }
    Color signed(double v) => v < 0 ? AppTheme.expense : AppTheme.income;

    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('نام پروژه', flex: 3, minWidth: 160),
        PinnedColumn('درآمد', flex: 3, minWidth: 140),
        PinnedColumn('بودجه اختصاص یافته', flex: 3, minWidth: 140),
        PinnedColumn('هزینه کرد', flex: 3, minWidth: 140),
        PinnedColumn('مانده هزینه', flex: 3, minWidth: 140),
        PinnedColumn('تراز کلی با احتساب بودجه', flex: 4, minWidth: 190),
        PinnedColumn('عملیات', flex: 2, minWidth: 150),
      ],
      onRowTap: (i) => _openProject(rows[i]),
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            Text('${i + 1}'),
            Text(rows[i].name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(formatNumber(rows[i].income)),
            Text(formatNumber(rows[i].budgetedIncome)),
            Text(formatNumber(rows[i].totalExpenses)),
            Text(formatNumber(rows[i].unapprovedExpenses)),
            Text(formatNumber(rows[i].balance),
                style: TextStyle(
                    color: signed(rows[i].balance),
                    fontWeight: FontWeight.w700)),
            TextButton.icon(
              onPressed: () => _openProject(rows[i]),
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('کارتابل پروژه'),
            ),
          ],
      ],
      footer: [
        const Text(''),
        const Text('جمع کل'),
        Text(formatNumber(state.totalIncome)),
        Text(formatNumber(state.totalBudget)),
        Text(formatNumber(state.totalExpenses)),
        Text(formatNumber(state.totalUnapproved)),
        Text(formatNumber(state.totalBalance)),
        const Text(''),
      ],
    );
  }
}
