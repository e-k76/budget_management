import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/search.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../widgets/ui_helpers.dart';
import 'entry_dialogs.dart';
import 'project_details_screen.dart';

/// Every income of every project, with search and a project filter.
class AllIncomesScreen extends StatefulWidget {
  const AllIncomesScreen({super.key});

  @override
  State<AllIncomesScreen> createState() => _AllIncomesScreenState();
}

class _AllIncomesScreenState extends State<AllIncomesScreen> {
  List<Income> _all = [];
  bool _loading = true;
  final _search = TextEditingController();
  String? _project;

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
      final rows = await state.allIncomes();
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

  List<Income> get _shown => _all.where((i) {
        if (_project != null && i.projectName != _project) return false;
        return matchesQuery([
          i.projectName,
          i.date,
          i.createdBy ?? '',
          i.amount.round().toString(),
        ], _search.text);
      }).toList();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = context.watch<AuthService>().currentUser!;
    final list = _shown;
    final total = list.fold<double>(0, (a, i) => a + i.amount);
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
                  child: Text('فهرست درآمدها',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (user.canEdit) ...[
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      if (await showIncomeDialog(context)) _load();
                    },
                    icon: const Icon(Icons.trending_up_rounded),
                    label: const Text('ثبت درآمد'),
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
                      hintText: 'جستجو در پروژه، تاریخ، مبلغ، ثبت‌کننده',
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
                Text('${list.length} از ${_all.length} مورد',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _all.isEmpty
                        ? Center(
                            child: Text('درآمدی ثبت نشده است.',
                                style: TextStyle(
                                    color: Theme.of(context).hintColor)))
                        : _table(list, total, state, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(List<Income> list, double total, AppState state, AppUser user) {
    final err = Theme.of(context).colorScheme.error;
    return PinnedTable(
      columns: const [
        PinnedColumn('ردیف', flex: 1, minWidth: 56),
        PinnedColumn('تاریخ', flex: 2, minWidth: 110),
        PinnedColumn('پروژه', flex: 3, minWidth: 150),
        PinnedColumn('مبلغ', flex: 3, minWidth: 160),
        PinnedColumn('ثبت‌کننده', flex: 3, minWidth: 140),
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
            Text(formatNumber(list[i].amount)),
            Text(displayUser(list[i].createdBy)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (user.canEdit)
                IconButton(
                  tooltip: 'ویرایش',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () async {
                    if (await showIncomeDialog(context, editing: list[i])) {
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
                        title: 'حذف درآمد',
                        message:
                            'مبلغ ${formatMoney(list[i].amount)} از درآمد پروژه «${list[i].projectName}» کسر و حذف شود؟');
                    if (ok) _guard(() => state.deleteIncome(list[i]));
                  },
                ),
            ]),
          ],
      ],
      footer: [
        const Text(''),
        const Text(''),
        const Text('جمع نمایش‌داده‌شده'),
        Text(formatNumber(total),
            style: const TextStyle(color: AppTheme.income)),
        const Text(''),
        const Text(''),
      ],
    );
  }
}
