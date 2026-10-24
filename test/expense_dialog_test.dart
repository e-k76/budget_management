import 'package:budget_management/models/models.dart';
import 'package:budget_management/providers/app_state.dart';
import 'package:budget_management/screens/entry_dialogs.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// AppState with no database: records what the dialog saves.
class _FakeState extends AppState {
  _FakeState(super.db, super.auth);

  final saved = <Expense>[];

  @override
  List<Project> get projects => const [
        Project(id: 1, name: 'Alpha', budgetPercentage: 100, totalIncome: 0),
      ];

  @override
  Future<void> saveExpense(Expense e) async => saved.add(e);
}

void main() {
  testWidgets('saving a new expense keeps the dialog open and resets it', (t) async {
    final db = DatabaseService.instance;
    final auth = AuthService(db);
    final state = _FakeState(db, auth);

    bool? closedWith;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppState>.value(value: state),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  closedWith = await showExpenseDialog(ctx, project: 'Alpha'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    Future<void> fillAndSave(String amount, String payee) async {
      await t.enterText(find.widgetWithText(TextFormField, 'مبلغ'), amount);
      await t.enterText(find.widgetWithText(TextFormField, 'در وجه'), payee);
      await t.tap(find.text('ثبت'));
      await t.pumpAndSettle();
    }

    expect(find.text('انصراف'), findsOneWidget);
    expect(
        t.widget<TextFormField>(find.widgetWithText(TextFormField, 'شرح')).controller!.text,
        'بدهی'); // default description

    await fillAndSave('1000', 'الست');

    // Still open, fields reset, confirmation shown, close button relabelled.
    expect(find.text('افزودن درخواست وجه'), findsOneWidget);
    expect(find.textContaining('ثبت شد (1 مورد)'), findsOneWidget);
    expect(find.text('بستن'), findsOneWidget);
    expect(
        t.widget<TextFormField>(find.widgetWithText(TextFormField, 'در وجه')).controller!.text,
        '');
    expect(
        t.widget<TextFormField>(find.widgetWithText(TextFormField, 'شرح')).controller!.text,
        'بدهی');

    await fillAndSave('2500', 'برمکی');
    expect(find.textContaining('ثبت شد (2 مورد)'), findsOneWidget);

    await t.tap(find.text('بستن'));
    await t.pumpAndSettle();
    expect(find.text('افزودن درخواست وجه'), findsNothing);
    expect(closedWith, isTrue); // caller reloads its list

    expect(state.saved.map((e) => e.amount), [1000, 2500]);
    expect(state.saved.map((e) => e.payee), ['الست', 'برمکی']);
    expect(state.saved.every((e) => e.projectName == 'Alpha' && e.description == 'بدهی'), isTrue);
  });

  testWidgets('cancel without saving returns false', (t) async {
    final db = DatabaseService.instance;
    final auth = AuthService(db);
    final state = _FakeState(db, auth);
    bool? closedWith;
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppState>.value(value: state),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async => closedWith = await showExpenseDialog(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.text('انصراف'));
    await t.pumpAndSettle();
    expect(closedWith, isFalse);
    expect(state.saved, isEmpty);
  });
}
