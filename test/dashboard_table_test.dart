import 'dart:io';

import 'package:budget_management/models/models.dart';
import 'package:budget_management/providers/app_state.dart';
import 'package:budget_management/screens/dashboard_screen.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:budget_management/services/db_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ProjectSummary s(String n, double inc, double total, double approved) => ProjectSummary(
      project: Project(id: 1, name: n, budgetPercentage: 100, totalIncome: inc),
      totalExpenses: total,
      approvedExpenses: approved,
      budgetPercentage: 100,
    );

void main() {
  late Directory tmp;
  late DatabaseService db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_dash');
    db = DatabaseService.instance
      ..localPathOverride = '${tmp.path}/local/projects.db'
      ..remoteEnabled = false;
    await db.init();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  testWidgets('dashboard list: «هزینه کرد» shows only the approved expenses of each project', (t) async {
    t.view.physicalSize = const Size(1800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    final auth = AuthService(db);
    await t.runAsync(() async {
      await auth.seedAdminIfEmpty();
      await auth.login('admin', 'admin123');
    });
    final state = AppState(db, auth)
      ..summaries = [
        s('Alpha', 1000000, 500000, 300000), // 300k approved + 200k unapproved
        s('Beta', 2000000, 123000, 123000), // all approved
      ];

    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DbStatus>(create: (_) => DbStatus(db)),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppState>.value(value: state),
      ],
      child: MaterialApp(
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Scaffold(body: DashboardScreen()),
      ),
    ));
    await t.pump();

    // per project: approved amounts (and the unapproved remainder for Alpha)
    expect(find.text('300,000'), findsWidgets); // Alpha, approved
    expect(find.text('123,000'), findsWidgets); // Beta, approved
    expect(find.text('200,000'), findsWidgets); // Alpha, «مانده هزینه»
    // the old (wrong) values must not be in the list: Alpha's TOTAL expenses, and the grand total
    expect(find.text('500,000'), findsNothing);
    expect(find.text('623,000'), findsNothing);
    // footer: sum of approved = 423,000
    expect(find.text('423,000'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
