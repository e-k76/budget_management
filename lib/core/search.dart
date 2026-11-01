import 'formatters.dart';

String _norm(String s) => normalizeDigits(s)
    .replaceAll(',', '')
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .toLowerCase()
    .trim();

/// True when [query] is empty or appears in any of [fields]. Persian/Arabic
/// digits, Arabic letter variants and thousands separators are ignored.
bool matchesQuery(Iterable<String> fields, String query) {
  final q = _norm(query);
  if (q.isEmpty) return true;
  return fields.any((f) => _norm(f).contains(q));
}
