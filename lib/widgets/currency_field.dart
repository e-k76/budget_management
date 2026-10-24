import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Live thousand-separator formatting (accepts Persian/Arabic digits).
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    final digits = Fmt.parseMoney(next.text.replaceAll(RegExp(r'[^\d۰-۹٠-٩]'), ''));
    if (digits == null) return const TextEditingValue();
    final t = Fmt.number(digits);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

class CurrencyField extends StatelessWidget {
  const CurrencyField({super.key, required this.controller, this.label = 'مبلغ', this.autofocus = false});
  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.number,
        inputFormatters: [ThousandsFormatter()],
        decoration: InputDecoration(labelText: label, suffixText: 'ریال'),
        validator: (v) {
          final n = Fmt.parseMoney(v ?? '');
          return (n == null || n <= 0) ? 'مبلغ معتبر وارد کنید' : null;
        },
      );
}
