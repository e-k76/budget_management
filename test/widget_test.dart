import 'package:budget_management/core/formatters.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  negativeFormatTests();
  group('formatters', () {
    test('money and parsing', () {
      expect(formatMoney(1234567), '1,234,567 ریال');
      expect(parseAmount('۱٬۲۳۴٬۵۶۷'), 1234567);
    });
    test('jalali parsing', () {
      expect(parseJalali('1403/12/30'), isNotNull); // 1403 is a leap year
      expect(parseJalali('1404/12/30'), isNull);
      expect(parseJalali('1403/13/01'), isNull);
      expect(monthKey('1403/5/12'), '1403/05');
    });
  });

  test('password hashing round-trips with salt', () {
    final h = AuthService.hashPassword('admin123');
    expect(AuthService.verifyPassword('admin123', h), isTrue);
    expect(AuthService.verifyPassword('wrong', h), isFalse);
    expect(h, isNot(AuthService.hashPassword('admin123')));
  });
}

void negativeFormatTests() {
  test('negative numbers keep the minus inside an LTR isolate', () {
    expect(formatNumber(-1500).codeUnits.first, 0x2066);
    expect(formatNumber(-1500).codeUnits.last, 0x2069);
    expect(formatNumber(1500), '1,500');
    expect(formatNumberPlain(-1500), '-1,500');
    expect(formatNumber(-0.2), '0');
  });
}
