import 'package:budget_management/widgets/temp_sum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clicking amounts toggles them in the temp sum; پاک کردن clears', (t) async {
    final amounts = {'a': 100.0, 'b': 250.0, 'c': 1000.0, 'd': 5.0};
    final picked = <String>{};
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          final total = picked.fold<double>(0, (s, k) => s + amounts[k]!);
          return Column(children: [
            TempSumBar(
                count: picked.length, total: total, onClear: () => setState(picked.clear)),
            for (final e in amounts.entries)
              PickableAmount(
                amount: e.value,
                picked: picked.contains(e.key),
                onTap: () => setState(() {
                  if (!picked.remove(e.key)) picked.add(e.key);
                }),
              ),
          ]);
        }),
      ),
    ));

    expect(find.text('جمع موقت'), findsOneWidget);
    expect(find.textContaining('0 ریال'), findsNothing); // nothing picked yet

    for (final v in ['100', '250', '1,000', '5']) {
      await t.tap(find.text(v));
      await t.pump();
    }
    expect(find.text('1,355 ریال'), findsOneWidget);
    expect(find.text('(4 مورد)'), findsOneWidget);

    await t.tap(find.text('1,000')); // click again -> removed
    await t.pump();
    expect(find.text('355 ریال'), findsOneWidget);
    expect(find.text('(3 مورد)'), findsOneWidget);

    await t.tap(find.text('پاک کردن'));
    await t.pump();
    expect(find.textContaining('ریال'), findsNothing);
    expect(find.textContaining('مورد)'), findsNothing);
  });

  test('approval filter allows the right rows', () {
    expect(ApprovalFilter.all.allows(true) && ApprovalFilter.all.allows(false), isTrue);
    expect(ApprovalFilter.approved.allows(true), isTrue);
    expect(ApprovalFilter.approved.allows(false), isFalse);
    expect(ApprovalFilter.unapproved.allows(false), isTrue);
    expect(ApprovalFilter.unapproved.allows(true), isFalse);
  });
}
