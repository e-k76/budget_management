import 'package:budget_management/core/sorting.dart';
import 'package:budget_management/widgets/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Row = ({int id, String date});

List<int> ids(List<Row> r) => r.map((e) => e.id).toList();

List<Row> sorted(List<Row> rows, bool asc) =>
    sortByDate<Row>(rows, date: (r) => r.date, id: (r) => r.id, ascending: asc);

void main() {
  final rows = <Row>[
    (id: 1, date: '1405/08/05'),
    (id: 2, date: '1405/9/1'), // not zero-padded: text order would put it after 1405/10/..
    (id: 3, date: '1405/10/01'),
    (id: 4, date: '1404/12/29'),
    (id: 5, date: '1405/08/05'), // same day as id 1
    (id: 6, date: 'garbage'),
  ];

  test('newest first sorts by the real date, not the text', () {
    // 10/01 > 09/01 > 08/05 (id 5 entered after id 1 comes first) > 1404; unreadable last
    expect(ids(sorted(rows, false)), [3, 2, 5, 1, 4, 6]);
  });

  test('oldest first; same-day rows keep entry order; unreadable still last', () {
    expect(ids(sorted(rows, true)), [4, 1, 5, 2, 3, 6]);
  });

  test('does not modify the input list and handles empty input', () {
    final copy = List<Row>.of(rows);
    sorted(rows, true);
    expect(rows, copy);
    expect(sorted(const [], false), isEmpty);
  });

  testWidgets('sortable header shows an arrow and reports clicks', (t) async {
    var asc = false;
    int? clicked;
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => SizedBox(
              height: 300,
              child: PinnedTable(
                sortColumn: 1,
                sortAscending: asc,
                onSort: (i) => set(() {
                  clicked = i;
                  asc = !asc;
                }),
                columns: const [
                  PinnedColumn('ردیف'),
                  PinnedColumn('تاریخ', sortable: true),
                  PinnedColumn('مبلغ'),
                ],
                rows: [
                  [const Text('1'), const Text('1405/01/01'), const Text('5')],
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget); // newest first
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
    await t.tap(find.text('تاریخ'));
    await t.pump();
    expect(clicked, 1);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget); // oldest first
    await t.tap(find.text('مبلغ')); // not sortable: nothing happens
    await t.pump();
    expect(clicked, 1);
  });
}
