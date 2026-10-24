import 'package:flutter/material.dart';

import '../utils/format.dart';

class JalaliDateField extends StatelessWidget {
  const JalaliDateField({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'تاریخ (۱۴۰۴/۰۱/۱۵)',
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final cur = Fmt.parseJalali(controller.text)?.toDateTime() ?? DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: cur,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: 'انتخاب تاریخ (میلادی، تبدیل به شمسی می‌شود)',
              );
              if (d != null) controller.text = Fmt.fromGregorian(d);
            },
          ),
        ),
        validator: (v) => Fmt.parseJalali(v ?? '') == null ? 'تاریخ شمسی معتبر وارد کنید' : null,
      );
}
