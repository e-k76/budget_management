import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/currency_field.dart';
import '../widgets/jalali_field.dart';
import '../widgets/ui.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense, this.projectName});
  final Expense? expense;
  final String? projectName;
  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _key = GlobalKey<FormState>();
  late final _date = TextEditingController(text: widget.expense?.date ?? Fmt.today());
  late final _amount = TextEditingController(text: widget.expense == null ? '' : Fmt.number(widget.expense!.amount));
  late final _pct = TextEditingController(text: widget.expense == null ? '' : '${widget.expense!.percentage}');
  late final _desc = TextEditingController(text: widget.expense?.description ?? '');
  String? _project;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _project = widget.expense?.projectName ?? widget.projectName;
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final s = context.read<AppState>();
    try {
      await s.saveExpense(Expense(
        id: widget.expense?.id,
        projectName: _project!,
        date: Fmt.fromGregorianOrKeep(_date.text),
        amount: Fmt.parseMoney(_amount.text)!,
        percentage: double.tryParse(_pct.text.trim()) ?? 0,
        description: _desc.text.trim(),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<AppState>().projects;
    return Scaffold(
      appBar: AppBar(title: Text(widget.expense == null ? 'افزودن درخواست وجه' : 'ویرایش هزینه')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _key,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                      initialValue: projects.any((p) => p.name == _project) ? _project : null,
                      decoration: const InputDecoration(labelText: 'نام پروژه'),
                      items: [for (final p in projects) DropdownMenuItem(value: p.name, child: Text(p.name))],
                      onChanged: (v) => setState(() => _project = v),
                      validator: (v) => v == null ? 'پروژه را انتخاب کنید' : null,
                    ),
                    const SizedBox(height: 16),
                    JalaliDateField(controller: _date),
                    const SizedBox(height: 16),
                    CurrencyField(controller: _amount),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pct,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'درصد', suffixText: '٪'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = double.tryParse(v.trim());
                        return (n == null || n < 0 || n > 100) ? 'عددی بین ۰ تا ۱۰۰' : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: 'شرح / ذینفع')),
                    const SizedBox(height: 24),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _save, child: const Text('ثبت'))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
