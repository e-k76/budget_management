import 'dart:io';

import 'package:budget_management/main.dart';
import 'package:budget_management/providers/app_state.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:budget_management/services/pending_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  }
  await t.pumpAndSettle();
}

void main() {
  testWidgets('login -> dashboard -> project -> forms -> scratchpad render without errors', (t) async {
    final tmp = Directory.systemTemp.createTempSync('bm_ui');
    DatabaseService.pathOverride = '${tmp.path}/projects.db';
    PendingQueue.pathOverride = '${tmp.path}/pending.json';
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final state = AppState();
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const App()));
    expect(find.text('ورود'), findsOneWidget);

    await t.enterText(find.byType(TextField).first, 'admin');
    await t.enterText(find.byType(TextField).last, 'admin123');
    await t.runAsync(() async {
      await t.tap(find.text('ورود'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await t.pumpAndSettle();
    expect(find.text('داشبورد اصلی'), findsOneWidget);

    await t.runAsync(() async {
      await state.addProject('پروژه الف');
      await state.addIncome('پروژه الف', 2000000, '1404/01/10');
      await state.saveExpenseForTest();
    });
    await t.pumpAndSettle();
    expect(find.text('پروژه الف'), findsWidgets);

    // project details (charts + tables)
    await t.ensureVisible(find.text('ورود به کارتابل'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('ورود به کارتابل'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(t);
    expect(find.textContaining('کارتابل پروژه'), findsOneWidget);
    expect(find.text('روند ماهانه'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();

    for (final label in ['افزودن درخواست وجه', 'افزایش درآمد', 'مدیریت کاربران', 'محیط موقت محاسبات']) {
      await t.ensureVisible(find.text(label));
      await t.pumpAndSettle();
      await t.tap(find.text(label));
      await settle(t);
      expect(find.byType(BackButton), findsOneWidget, reason: label);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });
}
