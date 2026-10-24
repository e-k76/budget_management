import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/search.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../widgets/kpi_card.dart';
import '../widgets/status_icons.dart';
import '../widgets/temp_sum.dart';
import '../widgets/ui_helpers.dart';
import 'entry_dialogs.dart';
import 'project_details_screen.dart';

enum _Status { all, approved, unapproved }

/// Every expense of every project, with search and filters.
class AllExpensesScreen extends StatefulWidget {
  const AllExpensesScreen({super.key});

  @override
  State<AllExpensesScreen> createState() => _AllExpensesScreenState();
}

class _AllExpensesScreenState extends State<AllExpensesScreen> {
  List<Expense> _all = [];
  bool _loading = true;
  final _search = TextEditingController();
  String? _project;
  _Status _status = _Status.all;

  // Amounts clicked into the temporary sum (by expense uid).
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    try {
      await state.refresh();
      final rows = await state.allExpenses();
      if (mounted) setState(() => _all = rows);
    } catch (e) {
      if (mounted) showSnack(context, 'خطا در بارگذاری: $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  Iterable<Expense> get _pickedRows => _all.where((e) => _picked.contains(e.uid));
  int get _pickedCount => _pickedRows.length;
  double get _pickedTotal => _pickedRows.fold<double>(0, (a, e) => a + e.amount);

  List<Expense> get _shown => _all.where((e) {
        if (_project != null && e.projectName != _project) return false;
        if (_status == _Status.approved && !e.isApproved) return false;
        if (_status == _Status.unapproved && e.isApproved) return false;
        return matchesQuery([
          e.projectName,
          e.payee,
          e.description,
          e.date,
          e.approvedAt ?? '',
          e.approvedBy ?? '',
          e.createdBy ?? '',
          e.amount.round().toString(),
        ], _search.text);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = context.watch<AuthService>().currentUser!;
    final list = _shown;
    final total = list.fold<double>(0, (a, e) => a + e.amount);
    final approved =
        list.where((e) => e.isApproved).fold<double>(0, (a, e) => a + e.amount);
    final names = state.projects.map((p) => p.name).toList();
    if (_project != null && !names.contains(_project)) _project = null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('فهرست هزینه‌ها',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (user.canEdit) ...[
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      if (await showExpenseDialog(context)) _load();
                    },
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('افزودن درخواست وجه'),
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton.filledTonal(
                  tooltip: 'بروزرسانی',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'جستجو (پروژه، در وجه، شرح، تاریخ، مبلغ)',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _project,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'پروژه', isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('همه پروژه‌ها')),
                      for (final n in names)
                        DropdownMenuItem(value: n, child: Text(n)),
                    ],
                    onChanged: (v) => setState(() => _project = v),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<_Status>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                        labelText: 'وضعیت تایید', isDense: true),
                    items: const [
                      DropdownMenuItem(value: _Status.all, child: Text('همه')),
                      DropdownMenuItem(
                          value: _Status.approved, child: Text('هزینه کرد')),
                      DropdownMenuItem(
                          value: _Status.unapproved, child: Text('مانده هزینه')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                ),
                Text('${list.length} از ${_all.length} مورد',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
            const SizedBox(height: 16),
            _totals(approved, total - approved, total),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _all.isEmpty
                        ? Center(
                            child: Text('هزینه‌ای ثبت نشده است.',
                                style: TextStyle(
                                    color: Theme.of(context).hintColor)))
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TempSumBar(
                                  count: _pickedCount,
                                  total: _pickedTotal,
                                  onClear: () => setState(_picked.clear),
                                ),
                              ),
                              Expanded(child: _table(list, total, state, user)),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Totals of the rows currently shown (they follow the search and filters).
  Widget _totals(double approved, double pending, double total) {
    final cards = [
      KpiCard(
          title: 'جمع هزینه کرد',
          value: formatMoney(approved),
          iconWidget: const DocStatusIcon(approved: true),
          color: DocStatusIcon.approvedColor),
      KpiCard(
          title: 'جمع مانده هزینه',
          value: formatMoney(pending),
          iconWidget: const DocStatusIcon(approved: false),
          color: DocStatusIcon.unapprovedColor),
      KpiCard(
          title: 'جمع کل مبالغ درخواستی',
          value: formatMoney(total),
          icon: Icons.summarize_rounded,
          color: AppTheme.seed),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 600 ? 2 : 1);
      const gap = 14.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    });
  }

  Widget _table(
      List<Expense> list, double total, AppState state, AppUser user) {
    final err = Theme.of(context).colorScheme.error;
    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('تاریخ', flex: 2, minWidth: 110),
        PinnedColumn('پروژه', flex: 3, minWidth: 150),
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
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      ProjectDetailsScreen(projectName: list[i].projectName))),
              child: Text(list[i].projectName),
            ),
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
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (user.canEdit)
                IconButton(
                  tooltip: 'ویرایش',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () async {
                    if (await showExpenseDialog(context, editing: list[i])) {
                      _load();
                    }
                  },
                ),
              if (user.canDelete)
                IconButton(
                  tooltip: 'حذف',
                  icon: Icon(Icons.delete_outline, size: 20, color: err),
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'حذف هزینه',
                        message:
                            'مبلغ ${formatMoney(list[i].amount)} (${list[i].projectName}) حذف شود؟');
                    if (ok) _guard(() => state.deleteExpense(list[i]));
                  },
                ),
            ]),
          ],
      ],
    );
  }
}
