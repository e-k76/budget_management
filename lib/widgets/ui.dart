import 'package:flutter/material.dart';

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ));
}

String errText(Object e) {
  final s = e.toString();
  if (s.contains('UNIQUE')) return 'این مقدار تکراری است';
  if (s.contains('database is locked')) return 'پایگاه داده در حال استفاده است، دوباره تلاش کنید';
  return s.replaceFirst('Bad state: ', '');
}

Future<bool> confirm(BuildContext c, String msg) async =>
    await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text('تأیید'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('بله')),
        ],
      ),
    ) ??
    false;
