import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatters.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../widgets/form_fields.dart';
import '../widgets/ui_helpers.dart';

/// Shared chrome for the small entry forms.
class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSave,
    required this.saving,
    this.width = 460,
    this.footer,
    this.closeLabel = 'انصراف',
    this.closeResult = false,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  final double width;

  /// Optional line under the fields (e.g. "saved" confirmation).
  final Widget? footer;
  final String closeLabel;

  /// Value returned when the dialog is closed with the close button.
  final bool closeResult;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: width,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in children) ...[c, const SizedBox(height: 14)],
                ?footer,
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, closeResult),
          child: Text(closeLabel),
        ),
        FilledButton.icon(
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('ثبت'),
        ),
      ],
    );
  }
}

Future<bool> showNewProjectDialog(BuildContext context) async {
  final r = await showDialog<bool>(
      context: context, builder: (_) => const _NewProjectDialog());
  return r ?? false;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();
  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().addProject(_name.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: 'تعریف پروژه جدید',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      width: 420,
      children: [
        TextFormField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'نام پروژه'),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'نام پروژه را وارد کنید' : null,
          onFieldSubmitted: (_) => _save(),
        ),
      ],
    );
  }
}

Future<bool> showBudgetPercentDialog(BuildContext context) async {
  final r = await showDialog<bool>(
      context: context, builder: (_) => const _BudgetDialog());
  return r ?? false;
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog();
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _form = GlobalKey<FormState>();
  late final _pct = TextEditingController(text: _initial());

  String _initial() {
    final v = context.read<AppState>().budgetPercentage;
    return v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
  }

  bool _saving = false;

  @override
  void dispose() {
    _pct.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AppState>().setBudgetPercentage(
          double.parse(normalizeDigits(_pct.text.trim())));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: 'درصد بودجه (برای تمامی پروژه‌ها)',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      width: 380,
      children: [
        TextFormField(
          controller: _pct,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration:
              const InputDecoration(labelText: 'درصد بودجه', suffixText: '%'),
          validator: (v) {
            final n = double.tryParse(normalizeDigits((v ?? '').trim()));
            return (n == null || n < 0 || n > 1000)
                ? 'عدد معتبر وارد کنید'
                : null;
          },
        ),
      ],
    );
  }
}

/// Add or edit an expense (درخواست وجه).
Future<bool> showExpenseDialog(BuildContext context,
    {Expense? editing, String? project}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _ExpenseDialog(editing: editing, initialProject: project),
  );
  return r ?? false;
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({this.editing, this.initialProject});
  final Expense? editing;
  final String? initialProject;
  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _form = GlobalKey<FormState>();
  late final _date =
      TextEditingController(text: widget.editing?.date ?? todayJalali());
  late final _amount = TextEditingController(
      text: widget.editing == null ? '' : formatNumber(widget.editing!.amount));
  late final _payee = TextEditingController(text: widget.editing?.payee ?? '');
  // New expenses default the description to "بدهی" (debt payment).
  late final _desc = TextEditingController(
      text: widget.editing == null ? 'بدهی' : widget.editing!.description);
  final _amountFocus = FocusNode();
  int _savedCount = 0;
  String? _lastSaved;
  String? _project;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = widget.editing?.projectName ?? widget.initialProject;
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _payee.dispose();
    _desc.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final e = widget.editing;
    final expense = Expense(
      id: e?.id,
      uid: e?.uid,
      projectName: _project!,
      date: formatJalali(parseJalali(_date.text)!),
      amount: parseAmount(_amount.text),
      payee: _payee.text.trim(),
      description: _desc.text.trim(),
    );
    try {
      await context.read<AppState>().saveExpense(expense);
      if (!mounted) return;
      if (e != null) {
        Navigator.pop(context, true); // editing: close as before
        return;
      }
      // New expense: stay open and reset the form for the next one. The
      // project stays selected, since several requests often go to one project.
      setState(() {
        _savedCount++;
        _lastSaved = '${expense.payee} — ${formatMoney(expense.amount)}';
        _saving = false;
        _amount.clear();
        _payee.clear();
        _desc.text = 'بدهی';
        _date.text = todayJalali();
      });
      _amountFocus.requestFocus();
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$err', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = context.read<AppState>().projects.map((p) => p.name).toList();
    if (_project != null && !names.contains(_project)) _project = null;
    return _FormDialog(
      title: widget.editing == null ? 'افزودن درخواست وجه' : 'ویرایش هزینه',
      closeLabel: _savedCount > 0 ? 'بستن' : 'انصراف',
      closeResult: _savedCount > 0,
      footer: _savedCount == 0
          ? null
          : Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF22A559), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ثبت شد ($_savedCount مورد): $_lastSaved',
                    style: const TextStyle(color: Color(0xFF22A559)),
                  ),
                ),
              ],
            ),
      formKey: _form,
      saving: _saving,
      onSave: _save,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _project,
          decoration: const InputDecoration(labelText: 'نام پروژه'),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
          ],
          onChanged: (v) => setState(() => _project = v),
          validator: (v) => v == null ? 'پروژه را انتخاب کنید' : null,
        ),
        JalaliDateField(controller: _date),
        CurrencyField(controller: _amount, focusNode: _amountFocus),
        TextFormField(
          controller: _payee,
          decoration: const InputDecoration(labelText: 'در وجه'),
          validator: (v) =>
              (v ?? '').trim().isEmpty ? 'نام دریافت‌کننده را وارد کنید' : null,
        ),
        TextFormField(
          controller: _desc,
          decoration: const InputDecoration(labelText: 'شرح'),
        ),
      ],
    );
  }
}

/// Add an income, or change the amount of an existing one.
Future<bool> showIncomeDialog(BuildContext context,
    {Income? editing, String? project}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => _IncomeDialog(editing: editing, initialProject: project),
  );
  return r ?? false;
}

class _IncomeDialog extends StatefulWidget {
  const _IncomeDialog({this.editing, this.initialProject});
  final Income? editing;
  final String? initialProject;
  @override
  State<_IncomeDialog> createState() => _IncomeDialogState();
}

class _IncomeDialogState extends State<_IncomeDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
      text: widget.editing == null ? '' : formatNumber(widget.editing!.amount));
  String? _project;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = widget.editing?.projectName ?? widget.initialProject;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final amount = parseAmount(_amount.text);
    try {
      if (widget.editing == null) {
        await state.addIncome(Income(
            projectName: _project!, amount: amount, date: todayJalali()));
      } else {
        await state.updateIncomeAmount(widget.editing!, amount);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (err) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$err', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = context.read<AppState>().projects.map((p) => p.name).toList();
    if (_project != null && !names.contains(_project)) _project = null;
    final editing = widget.editing != null;
    return _FormDialog(
      title: editing ? 'ویرایش درآمد' : 'افزودن درآمد',
      formKey: _form,
      saving: _saving,
      onSave: _save,
      width: 420,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _project,
          decoration: const InputDecoration(labelText: 'نام پروژه'),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
          ],
          onChanged: editing ? null : (v) => setState(() => _project = v),
          validator: (v) => v == null ? 'پروژه را انتخاب کنید' : null,
        ),
        CurrencyField(
            controller: _amount, label: 'مبلغ درآمد', autofocus: editing),
      ],
    );
  }
}
