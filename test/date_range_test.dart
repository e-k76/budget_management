import 'package:budget_management/core/date_range.dart';
import 'package:budget_management/widgets/date_range_filter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamsi_date/shamsi_date.dart';

void main() {
  group('DateRange.contains', () {
    test('no range matches everything, even odd dates', () {
      expect(const DateRange().contains('whatever'), isTrue);
    });

    test('inclusive bounds; stored dates need not be zero-padded', () {
      const r = DateRange(from: '1405/01/05', to: '1405/03/10');
      expect(r.contains('1405/01/05'), isTrue); // first day
      expect(r.contains('1405/3/10'), isTrue); // last day, unpadded
      expect(r.contains('1405/01/04'), isFalse);
      expect(r.contains('1405/03/11'), isFalse);
      expect(r.contains('۱۴۰۵/۰۲/۰۱'), isTrue); // Persian digits
      expect(r.contains('1404/12/29'), isFalse);
    });

    test('open-ended ranges', () {
      expect(const DateRange(from: '1405/06/01').contains('1406/01/01'), isTrue);
      expect(const DateRange(from: '1405/06/01').contains('1405/05/31'), isFalse);
      expect(const DateRange(to: '1405/06/01').contains('1400/01/01'), isTrue);
      expect(const DateRange(to: '1405/06/01').contains('1405/06/02'), isFalse);
    });

    test('unparseable dates are excluded once a range is active', () {
      expect(const DateRange(from: '1405/01/01').contains('not a date'), isFalse);
    });

    test('inverted range matches nothing', () {
      const r = DateRange(from: '1405/05/01', to: '1405/01/01');
      expect(r.isInverted, isTrue);
      expect(r.contains('1405/03/01'), isFalse);
    });

    test('describe', () {
      expect(const DateRange(from: '1405/01/01', to: '1405/02/01').describe(),
          'از تاریخ 1405/01/01 تا تاریخ 1405/02/01');
      expect(const DateRange(to: '1405/02/01').describe(), 'تا تاریخ 1405/02/01');
    });
  });

  test('presets', () {
    final today = Jalali(1405, 8, 10);
    expect(DateRange.thisMonth(today), const DateRange(from: '1405/08/01', to: '1405/08/30'));
    expect(DateRange.lastMonth(today), const DateRange(from: '1405/07/01', to: '1405/07/30'));
    expect(DateRange.lastMonth(Jalali(1405, 1, 3)), const DateRange(from: '1404/12/01', to: '1404/12/29'));
    expect(DateRange.thisYear(today).from, '1405/01/01');
    expect(DateRange.thisYear(today).to, '1405/12/29');
    expect(DateRange.last30Days(today), const DateRange(from: '1405/07/10', to: '1405/08/10'));
  });

  group('DateRangeFilter widget', () {
    late DateRange current;

    Future<void> pump(WidgetTester t) async {
      current = const DateRange();
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => DateRangeFilter(
                  range: current, onChanged: (r) => set(() => current = r)),
            ),
          ),
        ),
      ));
    }

    testWidgets('typing valid dates sets the range; invalid ones are flagged', (t) async {
      await pump(t);
      final boxes = find.byType(TextField);
      await t.enterText(boxes.at(0), '1405/1/5');
      await t.pump();
      expect(current.from, '1405/01/05');
      expect(current.to, isNull);
      await t.enterText(boxes.at(1), '1405/13/40');
      await t.pump();
      expect(find.text('تاریخ نامعتبر'), findsOneWidget);
      expect(current.to, isNull);
      await t.enterText(boxes.at(1), '1405/01/01');
      await t.pump();
      expect(find.text('قبل از تاریخ شروع'), findsOneWidget);
    });

    testWidgets('preset fills both boxes; clear empties them', (t) async {
      await pump(t);
      await t.tap(find.byIcon(Icons.date_range_outlined));
      await t.pumpAndSettle();
      await t.tap(find.text('این ماه'));
      await t.pumpAndSettle();
      expect(current.isActive, isTrue);
      expect(current.from, endsWith('/01'));
      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields[0].controller!.text, current.from);
      expect(fields[1].controller!.text, current.to);

      await t.tap(find.byTooltip('حذف بازه تاریخ'));
      await t.pumpAndSettle();
      expect(current.isActive, isFalse);
      final cleared = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(cleared[0].controller!.text, isEmpty);
      expect(cleared[1].controller!.text, isEmpty);
    });
  });
}
