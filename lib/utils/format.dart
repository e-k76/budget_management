import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';

class Fmt {
  static final _n = NumberFormat('#,##0');
  static String number(num v) => _n.format(v.round());
  static String money(num v) => '${number(v)} ریال';
  static String percent(num v) => '${v % 1 == 0 ? v.toInt() : v.toStringAsFixed(1)}٪';

  static String jalali(Jalali j) =>
      '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  static String today() => jalali(Jalali.now());
  static String fromGregorian(DateTime d) => jalali(Jalali.fromDateTime(d));

  /// Normalises a (validated) typed date to zero-padded latin `yyyy/mm/dd`.
  static String fromGregorianOrKeep(String s) {
    final j = parseJalali(s);
    return j == null ? s : jalali(j);
  }

  static Jalali? parseJalali(String s) {
    final m = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(_latinDigits(s.trim()));
    if (m == null) return null;
    try {
      final j = Jalali(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      return j.isValid() ? j : null;
    } catch (_) {
      return null;
    }
  }

  static String _latinDigits(String s) {
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final c in s.split('')) {
      final i = fa.indexOf(c) >= 0 ? fa.indexOf(c) : ar.indexOf(c);
      b.write(i >= 0 ? '$i' : c);
    }
    return b.toString();
  }

  /// Parses "1,234,567" (also Persian digits) into a number.
  static double? parseMoney(String s) {
    final t = _latinDigits(s).replaceAll(RegExp(r'[,،\s]'), '');
    return double.tryParse(t);
  }
}
