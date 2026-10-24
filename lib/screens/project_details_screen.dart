import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/search.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../widgets/charts.dart';
import '../widgets/kpi_card.dart';
import '../widgets/status_icons.dart';
import '../widgets/temp_sum.dart';
import '../widgets/ui_helpers.dart';
import 'entry_dialogs.dart';

class ProjectDetailsScreen extends StatefulWidget {
  const ProjectDetailsScreen({super.key, required this.projectName});

  final String projectName;

  @override
  State<ProjectDetailsScreen> createState() => _ProjectDetailsScreenState();
}

class _ProjectDetailsScreenState extends State<ProjectDetailsScreen> {
  List<Expense> _expenses = [];
  List<Income> _incomes = [];
  bool _loading = true;
  final _expenseSearch = TextEditingController();
  final _incomeSearch = TextEditingController();

  // Expenses tab: approval filter and the amounts clicked into the temp sum.
  ApprovalFilter _approval = ApprovalFilter.all;
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _expenseSearch.dispose();
    _incomeSearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    try {
      await state.refresh();
      final e = await state.expensesOf(widget.projectName);
      final i = await state.incomesOf(widget.projectName);
      if (!mounted) return;
      setState(() {
        _expenses = e;
        _incomes = i;
        _loading = false;
      });
    } catch (err) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, 'خطا در بارگذاری: $err', error: true);
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  // ---------------------------------------------------------------- search

  List<Expense> get _shownExpenses => _expenses
      .where((e) => _approval.allows(e.isApproved) &&
          matchesQuery([
            e.payee,
            e.description,
            e.date,
            e.approvedAt ?? '',
            e.approvedBy ?? '',
            e.createdBy ?? '',
            e.amount.round().toString(),
          ], _expenseSearch.text))
      .toList();

  List<Income> get _shownIncomes => _incomes
      .where((i) => matchesQuery([
            i.date,
            i.createdBy ?? '',
            i.amount.round().toString(),
          ], _incomeSearch.text))
      .toList();

  Widget _searchBar(TextEditingController c, String hint, int shown, int total,
      {List<Widget> extra = const []}) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: c,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: c.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(c.clear),
                      ),
              ),
            ),
          ),
          ...extra,
          Text('$shown از $total',
              style: TextStyle(color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = context.watch<AuthService>().currentUser!;
    ProjectSummary? summary;
    for (final s in state.summaries) {
      if (s.name == widget.projectName) summary = s;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text('کارتابل پروژه: ${widget.projectName}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading || summary == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, c) {
              final s = summary!;
              final pinned = <Widget>[
                _actions(context, user, s),
                const SizedBox(height: 16),
                _kpis(s),
                const SizedBox(height: 16),
              ];
              // Actions and KPIs stay pinned; only the tab content scrolls.
              // On very short windows fall back to scrolling the whole page.
              if (c.maxHeight < 600) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ...pinned,
                    SizedBox(height: 460, child: _tabs(state, user, s)),
                  ],
                );
              }
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...pinned, Expanded(child: _tabs(state, user, s))],
                ),
              );
            }),
    );
  }

  Widget _tabs(AppState state, AppUser user, ProjectSummary s) {
    return DefaultTabController(
      length: 3,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'درخواست‌های وجه / هزینه‌ها'),
                Tab(text: 'درآمدها'),
                Tab(text: 'نمودارها'),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _expensesTab(state, user),
                  _incomesTab(state, user, s),
                  ListView(
                    padding: const EdgeInsets.all(18),
                    children: [_charts(s)],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppUser user, ProjectSummary s) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (user.canEdit) ...[
          FilledButton.tonalIcon(
            onPressed: () async {
              if (await showExpenseDialog(context, project: s.name)) _load();
            },
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('افزودن درخواست وجه'),
          ),
          FilledButton.tonalIcon(
            onPressed: () async {
              if (await showIncomeDialog(context, project: s.name)) _load();
            },
            icon: const Icon(Icons.trending_up_rounded),
            label: const Text('افزایش درآمد'),
          ),
        ],
      ],
    );
  }

  Widget _kpis(ProjectSummary s) {
    final cards = [
      KpiCard(
          title: 'درآمد کلی',
          value: formatMoney(s.income),
          icon: Icons.south_west_rounded,
          color: AppTheme.income),
      KpiCard(
          title: 'هزینه تاییدشده',
          value: formatMoney(s.approvedExpenses),
          iconWidget: const DocStatusIcon(approved: true),
          color: DocStatusIcon.approvedColor),
      KpiCard(
          title: 'هزینه تاییدنشده',
          value: formatMoney(s.totalExpenses - s.approvedExpenses),
          iconWidget: const DocStatusIcon(approved: false),
          color: DocStatusIcon.unapprovedColor),
      KpiCard(
          title: 'بودجه',
          value: formatMoney(s.budgetedIncome),
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF0EA5E9)),
      KpiCard(
          title: 'تراز با درصد بودجه',
          value: formatMoney(s.balance),
          icon: Icons.balance_rounded,
          color: AppTheme.seed),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1250
          ? 5
          : (c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1));
      const gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    });
  }

  // ---------------------------------------------------------------- charts

  Map<String, double> _monthly(Iterable<(String, double)> items) {
    final m = <String, double>{};
    for (final (date, amount) in items) {
      m.update(monthKey(date), (v) => v + amount, ifAbsent: () => amount);
    }
    return m;
  }

  Widget _charts(ProjectSummary s) {
    return ChartGrid(children: [
      ChartCard(title: 'تفکیک درآمد و هزینه', child: ApprovalPie(s)),
      ChartCard(
        title: 'روند ماهانه درآمد و هزینه',
        child: MonthlyTrendChart(
          income: _monthly(_incomes.map((i) => (i.date, i.amount))),
          expense: _monthly(_expenses.map((e) => (e.date, e.amount))),
        ),
      ),
      ChartCard(
          title: 'هزینه ماهانه تاییدشده و تاییدنشده',
          child: MonthlyApprovalBars(_expenses)),
      ChartCard(
          title: 'بیشترین دریافت‌کنندگان', child: TopPayeesBars(_expenses)),
    ]);
  }

  Widget _empty(String text) => Center(
        child: Text(text, style: TextStyle(color: Theme.of(context).hintColor)),
      );

  // ---------------------------------------------------------------- tables

  Widget _rowActions({
    required bool canEdit,
    required bool canDelete,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final err = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canEdit)
          IconButton(
            tooltip: 'ویرایش',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
        if (canDelete)
          IconButton(
            tooltip: 'حذف',
            icon: Icon(Icons.delete_outline, size: 20, color: err),
            onPressed: onDelete,
          ),
      ],
    );
  }

  Widget _expensesTab(AppState state, AppUser user) {
    final list = _shownExpenses;
    final pickedTotal = _expenses
        .where((e) => _picked.contains(e.uid))
        .fold<double>(0, (a, e) => a + e.amount);
    final pickedCount = _expenses.where((e) => _picked.contains(e.uid)).length;
    return Column(
      children: [
        _searchBar(
          _expenseSearch,
          'جستجو (در وجه، شرح، تاریخ، مبلغ)',
          list.length,
          _expenses.length,
          extra: [
            ApprovalFilterField(
                value: _approval,
                onChanged: (v) => setState(() => _approval = v)),
          ],
        ),
        TempSumBar(
          count: pickedCount,
          total: pickedTotal,
          onClear: () => setState(_picked.clear),
        ),
        Expanded(
          child: _expenses.isEmpty
              ? _empty('هزینه‌ای ثبت نشده است.')
              : list.isEmpty
                  ? _empty('موردی یافت نشد.')
                  : _expensesTable(list, state, user),
        ),
      ],
    );
  }

  Widget _expensesTable(List<Expense> list, AppState state, AppUser user) {
    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('تاریخ', flex: 2, minWidth: 110),
        PinnedColumn('مبلغ', flex: 3, minWidth: 140),
        PinnedColumn('در وجه', flex: 3, minWidth: 150),
        PinnedColumn('شرح', flex: 4, minWidth: 200),
        PinnedColumn('وضعیت تایید', flex: 2, minWidth: 110),
        PinnedColumn('تاییدکننده', flex: 2, minWidth: 130),
        PinnedColumn('تاریخ تایید', flex: 2, minWidth: 110),
        PinnedColumn('عملیات', flex: 2, minWidth: 110),
      ],
      rows: [
        for (var i = 0; i < list.length; i++)
          [
            Text('${i + 1}'),
            Text(list[i].date),
            PickableAmount(
              amount: list[i].amount,
              picked: _picked.contains(list[i].uid),
              onTap: () => setState(() {
                final id = list[i].uid!;
                if (!_picked.remove(id)) _picked.add(id);
              }),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(list[i].payee,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(list[i].description,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Checkbox(
              value: list[i].isApproved,
              onChanged: user.canEdit
                  ? (v) => _guard(() => state.setApproval(list[i], v ?? false))
                  : null,
            ),
            Text(displayUser(list[i].approvedBy)),
            Text(list[i].approvedAt ?? '-'),
            _rowActions(
              canEdit: user.canEdit,
              canDelete: user.canDelete,
              onEdit: () async {
                if (await showExpenseDialog(context, editing: list[i])) _load();
              },
              onDelete: () async {
                final ok = await confirmDialog(context,
                    title: 'حذف هزینه',
                    message: 'مبلغ ${formatMoney(list[i].amount)} حذف شود؟');
                if (ok) _guard(() => state.deleteExpense(list[i]));
              },
            ),
          ],
      ],
    );
  }

  Widget _incomesTab(AppState state, AppUser user, ProjectSummary s) {
    final list = _shownIncomes;
    final legacy = s.income - _incomes.fold<double>(0, (a, i) => a + i.amount);
    return Column(
      children: [
        _searchBar(_incomeSearch, 'جستجو در تاریخ، مبلغ، ثبت‌کننده', list.length,
            _incomes.length),
        Expanded(
          child: _incomes.isEmpty
              ? _empty('درآمدی ثبت نشده است.')
              : list.isEmpty
                  ? _empty('موردی یافت نشد.')
                  : _incomesTable(list, state, user),
        ),
        if (legacy.abs() > 0.5)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'توجه: ${formatMoney(legacy)} از درآمد کلی بدون ردیف جزئیات ثبت شده است.',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
      ],
    );
  }

  Widget _incomesTable(List<Income> list, AppState state, AppUser user) {
    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('تاریخ', flex: 2, minWidth: 110),
        PinnedColumn('مبلغ', flex: 3, minWidth: 160),
        PinnedColumn('ثبت‌کننده', flex: 3, minWidth: 140),
        PinnedColumn('عملیات', flex: 2, minWidth: 110),
      ],
      rows: [
        for (var i = 0; i < list.length; i++)
          [
            Text('${i + 1}'),
            Text(list[i].date),
            Text(formatNumber(list[i].amount)),
            Text(displayUser(list[i].createdBy)),
            _rowActions(
              canEdit: user.canEdit,
              canDelete: user.canDelete,
              onEdit: () async {
                if (await showIncomeDialog(context, editing: list[i])) _load();
              },
              onDelete: () async {
                final ok = await confirmDialog(context,
                    title: 'حذف درآمد',
                    message:
                        'مبلغ ${formatMoney(list[i].amount)} از درآمد پروژه کسر و حذف شود؟');
                if (ok) _guard(() => state.deleteIncome(list[i]));
              },
            ),
          ],
      ],
    );
  }
}
