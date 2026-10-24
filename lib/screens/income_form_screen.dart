import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/income.dart';
import '../providers/app_state.dart';
import '../utils/format.dart';
import '../widgets/currency_field.dart';
import '../widgets/jalali_field.dart';
import '../widgets/ui.dart';

class IncomeFormScreen extends StatefulWidget {
  const IncomeFormScreen({super.key, this.income, this.projectName});
  final Income? income;
  final String? projectName;
  @override
  State<IncomeFormScreen> createState() => _IncomeFormScreenState();
}

class _IncomeFormScreenState extends State<IncomeFormScreen> {
  final _key = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.income == null ? '' : Fmt.number(widget.income!.amount));
  late final _date = TextEditingController(
      text: (widget.income?.date.isNotEmpty ?? false) ? widget.income!.date : Fmt.today());
  String? _project;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _project = widget.income?.projectName ?? widget.projectName;
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    final s = context.read<AppState>();
    final amount = Fmt.parseMoney(_amount.text)!;
    final date = Fmt.fromGregorianOrKeep(_date.text);
    try {
      if (widget.income == null) {
        await s.addIncome(_project!, amount, date);
      } else {
        await s.updateIncome(widget.income!.id!, amount, date);
      }
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
    final editing = widget.income != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'ویرایش درآمد' : 'افزودن درآمد')),
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
                      value: projects.any((p) => p.name == _project) ? _project : null,
                      decoration: const InputDecoration(labelText: 'نام پروژه'),
                      items: [for (final p in projects) DropdownMenuItem(value: p.name, child: Text(p.name))],
                      onChanged: editing ? null : (v) => setState(() => _project = v),
                      validator: (v) => v == null ? 'پروژه را انتخاب کنید' : null,
                    ),
                    const SizedBox(height: 16),
                    JalaliDateField(controller: _date),
                    const SizedBox(height: 16),
                    CurrencyField(controller: _amount, label: 'مبلغ درآمد'),
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
