import 'formatters.dart';

/// Sort key for a stored Jalali date (any format, e.g. `1405/9/1`); -1 when unreadable.
int dateKey(String date) {
  final j = parseJalali(date);
  return j == null ? -1 : j.year * 10000 + j.month * 100 + j.day;
}

/// Sorts by the real calendar date (not the text, so `1405/9/1` < `1405/10/1`).
/// Equal dates keep entry order (by [id], same direction). Unreadable dates always go last.
List<T> sortByDate<T>(
  Iterable<T> items, {
  required String Function(T) date,
  required int Function(T) id,
  required bool ascending,
}) {
  final list = items.toList();
  final keys = {for (final x in list) x: dateKey(date(x))};
  list.sort((a, b) {
    final ka = keys[a]!, kb = keys[b]!;
    if (ka < 0 || kb < 0) {
      if (ka < 0 && kb < 0) return id(a).compareTo(id(b));
      return ka < 0 ? 1 : -1;
    }
    final c = ka.compareTo(kb);
    if (c != 0) return ascending ? c : -c;
    final t = id(a).compareTo(id(b));
    return ascending ? t : -t;
  });
  return list;
}
