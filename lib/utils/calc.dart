/// Tiny safe expression evaluator: + - * / ( ) unary minus, decimals.
/// Accepts × ÷ and Persian digits; throws FormatException on bad input.
class Calc {
  static double eval(String input) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    var s = input.replaceAll(RegExp(r'[,\s،]'), '').replaceAll('×', '*').replaceAll('÷', '/').replaceAll('٪', '%');
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(fa[i], '$i');
    }
    final p = _Parser(s);
    final v = p.expr();
    if (p.i != s.length) throw const FormatException('عبارت نامعتبر');
    if (v.isNaN || v.isInfinite) throw const FormatException('تقسیم بر صفر');
    return v;
  }
}

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  String? get _c => i < s.length ? s[i] : null;

  double expr() {
    var v = term();
    while (_c == '+' || _c == '-') {
      final op = s[i++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = unary();
    while (_c == '*' || _c == '/') {
      final op = s[i++];
      final r = unary();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double unary() {
    if (_c == '-') { i++; return -unary(); }
    if (_c == '+') { i++; return unary(); }
    var v = primary();
    while (_c == '%') { i++; v /= 100; }
    return v;
  }

  double primary() {
    if (_c == '(') {
      i++;
      final v = expr();
      if (_c != ')') throw const FormatException('پرانتز بسته نشده');
      i++;
      return v;
    }
    final m = RegExp(r'\d+(\.\d+)?|\.\d+').matchAsPrefix(s, i);
    if (m == null) throw const FormatException('عبارت نامعتبر');
    i = m.end;
    return double.parse(m[0]!);
  }
}
