import 'package:flutter_test/flutter_test.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/utils/calc.dart';
import 'package:budget_management/utils/format.dart';

void main() {
  test('calc', () {
    expect(Calc.eval('1,200 × 3 ÷ 4'), 900);
    expect(Calc.eval('-(2+3)*2'), -10);
    expect(Calc.eval('50%'), .5);
    expect(() => Calc.eval('1/0'), throwsFormatException);
    expect(() => Calc.eval('2+'), throwsFormatException);
  });
  test('format', () {
    expect(Fmt.money(1234567), '1,234,567 ریال');
    expect(Fmt.parseMoney('۱,۲۳۴'), 1234);
    expect(Fmt.parseJalali('1404/13/01'), isNull);
    expect(Fmt.parseJalali('1404/1/5'), isNotNull);
  });
  test('password hashing', () {
    final h = AuthService.hashPassword('admin123');
    expect(AuthService.verify('admin123', h), isTrue);
    expect(AuthService.verify('x', h), isFalse);
  });
}
