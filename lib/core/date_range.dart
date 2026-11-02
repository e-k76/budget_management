import 'package:shamsi_date/shamsi_date.dart';

import 'formatters.dart';

/// Inclusive Jalali date range used by the list filters. [from]/[to] are
/// normalized `yyyy/MM/dd` strings (null = open-ended).
class DateRange {
  const DateRange({this.from, this.to});

  final String? from;
  final String? to;

  bool get isActive => from != null || to != null;

  /// from > to: nothing can match.
  bool get isInverted => from != null && to != null && from!.compareTo(to!) > 0;

  /// Whether [date] (any stored format, e.g. `1405/1/5`) falls inside the range.
  /// With an active range, unparseable dates are excluded.
  bool contains(String date) {
    if (!isActive) return true;
    final j = parseJalali(date);
    if (j == null) return false;
    final d = formatJalali(j);
    if (from != null && d.compareTo(from!) < 0) return false;
    if (to != null && d.compareTo(to!) > 0) return false;
    return true;
  }

  /// For report headers, e.g. `از تاریخ 1405/01/01 تا تاریخ 1405/03/31`.
  String describe() => [
        if (from != null) 'از تاریخ $from',
        if (to != null) 'تا تاریخ $to',
      ].join(' ');

  static DateRange between(Jalali a, Jalali b) =>
      DateRange(from: formatJalali(a), to: formatJalali(b));

  static DateRange thisMonth(Jalali today) => between(
      Jalali(today.year, today.month, 1),
      Jalali(today.year, today.month, today.monthLength));

  static DateRange lastMonth(Jalali today) {
    final first = Jalali(today.year, today.month, 1).addMonths(-1);
    return between(first, Jalali(first.year, first.month, first.monthLength));
  }

  static DateRange thisYear(Jalali today) =>
      between(Jalali(today.year, 1, 1), Jalali(today.year, 12, Jalali(today.year, 12, 1).monthLength));

  static DateRange last30Days(Jalali today) => between(today.addDays(-30), today);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}
