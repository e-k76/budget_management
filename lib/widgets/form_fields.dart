import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/formatters.dart';

/// Re-formats digits with thousands separators as the user types.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits =
        normalizeDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = formatNumber(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.controller,
    this.label = 'مبلغ',
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      inputFormatters: [ThousandsFormatter()],
      decoration: InputDecoration(labelText: label, suffixText: 'ریال'),
      validator: (v) {
        if (parseAmount(v ?? '') <= 0) return 'مبلغ را وارد کنید';
        return null;
      },
    );
  }
}

class PercentField extends StatelessWidget {
  const PercentField({
    super.key,
    required this.controller,
    this.label = 'درصد',
    this.max = 100,
  });

  final TextEditingController controller;
  final String label;
  final double max;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, suffixText: '%'),
      validator: (v) {
        final text = (v ?? '').trim();
        if (text.isEmpty) return null;
        final n = double.tryParse(normalizeDigits(text));
        if (n == null || n < 0 || n > max) return 'عدد معتبر وارد کنید';
        return null;
      },
    );
  }
}

class JalaliDateField extends StatelessWidget {
  const JalaliDateField({
    super.key,
    required this.controller,
    this.label = 'تاریخ',
  });

  final TextEditingController controller;
  final String label;

  Future<void> _pick(BuildContext context) async {
    final initial = parseJalali(controller.text) ?? Jalali.now();
    final picked = await showDialog<Jalali>(
      context: context,
      builder: (_) => _JalaliPickerDialog(initial: initial),
    );
    if (picked != null) controller.text = formatJalali(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      textDirection: TextDirection.ltr,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: '1403/01/01',
        suffixIcon: IconButton(
          tooltip: 'انتخاب تاریخ',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => _pick(context),
        ),
      ),
      validator: (v) =>
          parseJalali(v ?? '') == null ? 'تاریخ معتبر نیست (سال/ماه/روز)' : null,
    );
  }
}

class _JalaliPickerDialog extends StatefulWidget {
  const _JalaliPickerDialog({required this.initial});
  final Jalali initial;

  @override
  State<_JalaliPickerDialog> createState() => _JalaliPickerDialogState();
}

class _JalaliPickerDialogState extends State<_JalaliPickerDialog> {
  late int year = widget.initial.year;
  late int month = widget.initial.month;
  late int day = widget.initial.day;

  int get _daysInMonth => Jalali(year, month, 1).monthLength;

  @override
  Widget build(BuildContext context) {
    final nowYear = Jalali.now().year;
    if (day > _daysInMonth) day = _daysInMonth;
    return AlertDialog(
      title: const Text('انتخاب تاریخ'),
      content: SizedBox(
        width: 380,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                initialValue: year,
                decoration: const InputDecoration(labelText: 'سال'),
                items: [
                  for (var y = nowYear - 15; y <= nowYear + 5; y++)
                    DropdownMenuItem(value: y, child: Text('$y')),
                ],
                onChanged: (v) => setState(() => year = v ?? year),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<int>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'ماه'),
                items: [
                  for (var m = 1; m <= 12; m++)
                    DropdownMenuItem(
                        value: m, child: Text(jalaliMonthNames[m - 1])),
                ],
                onChanged: (v) => setState(() => month = v ?? month),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<int>(
                key: ValueKey('$year-$month'),
                initialValue: day,
                decoration: const InputDecoration(labelText: 'روز'),
                items: [
                  for (var d = 1; d <= _daysInMonth; d++)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => day = v ?? day),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        TextButton(
          onPressed: () => setState(() {
            final n = Jalali.now();
            year = n.year;
            month = n.month;
            day = n.day;
          }),
          child: const Text('امروز'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, Jalali(year, month, day)),
          child: const Text('تایید'),
        ),
      ],
    );
  }
}
