import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';

final NumberFormat _grouped = NumberFormat('#,##0');

const List<String> jalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

/// Converts Persian/Arabic-Indic digits and separators to ASCII.
String normalizeDigits(String input) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final buf = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final p = persian.indexOf(ch);
    final a = arabic.indexOf(ch);
    if (p >= 0) {
      buf.write(p);
    } else if (a >= 0) {
      buf.write(a);
    } else if (ch == '٬' || ch == '،') {
      buf.write(',');
    } else if (ch == '٫') {
      buf.write('.');
    } else {
      buf.write(ch);
    }
  }
  return buf.toString();
}

/// Negative numbers are wrapped in an LTR isolate so the minus sign stays on
/// the left of the digits inside right-to-left text.
String formatNumber(num value) {
  final s = formatNumberPlain(value);
  return s.startsWith('-') ? '$_lri$s$_pdi' : s;
}

// Unicode LEFT-TO-RIGHT ISOLATE (U+2066) and POP DIRECTIONAL ISOLATE (U+2069).
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// Grouped number with no direction-control characters (for the PDF, whose
/// bidi engine doesn't support isolates).
String formatNumberPlain(num value) =>
    value.round() == 0 ? '0' : _grouped.format(value);

String formatMoney(num value) => '${formatNumber(value)} ریال';

String formatPercent(num value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text%';
}

/// Parses user text such as "1,250,000" or "۱٬۲۵۰٬۰۰۰" into a number.
double parseAmount(String text) {
  final cleaned = normalizeDigits(text).replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(cleaned) ?? 0;
}

String formatJalali(Jalali j) =>
    '${j.year.toString().padLeft(4, '0')}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';

String todayJalali() => formatJalali(Jalali.now());

/// Parses "yyyy/MM/dd" (any digit script). Returns null when invalid.
Jalali? parseJalali(String text) {
  final m = RegExp(r'^(\d{4})[/\-](\d{1,2})[/\-](\d{1,2})$')
      .firstMatch(normalizeDigits(text.trim()));
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1) return null;
  if (d > Jalali(y, mo, 1).monthLength) return null;
  return Jalali(y, mo, d);
}

/// "1403/05/12" -> "1403/05" for monthly grouping.
String monthKey(String jalaliDate) {
  final parts = normalizeDigits(jalaliDate).split('/');
  if (parts.length < 2) return jalaliDate;
  return '${parts[0]}/${parts[1].padLeft(2, '0')}';
}

String monthLabel(String key) {
  final parts = key.split('/');
  if (parts.length < 2) return key;
  final m = int.tryParse(parts[1]) ?? 1;
  return '${jalaliMonthNames[(m - 1).clamp(0, 11)]} ${parts[0]}';
}

/// Name shown for a stored creator/approver. Rows brought over from the old
/// Access database carry the marker "Access import" instead of a person.
String displayUser(String? stored) {
  final s = (stored ?? '').trim();
  if (s.isEmpty) return '-';
  return s == 'Access import' ? 'اکسس (قدیمی)' : s;
}
