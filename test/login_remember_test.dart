import 'dart:io';

import 'package:budget_management/screens/login_screen.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/services/credential_store.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tmp;
  late DatabaseService db;
  late AuthService auth;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_login');
    db = DatabaseService.instance
      ..localPathOverride = '${tmp.path}/local/projects.db'
      ..remoteEnabled = false;
    await db.init();
    auth = AuthService(db);
    await auth.seedAdminIfEmpty();
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpLogin(WidgetTester t, CredentialStore store) async {
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<CredentialStore>.value(value: store),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: const MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: LoginScreen()),
      ),
    ));
    await t.pumpAndSettle();
  }

  String fieldText(WidgetTester t, int i) =>
      t.widgetList<TextFormField>(find.byType(TextFormField)).elementAt(i).controller!.text;

  Future<void> submit(WidgetTester t, String u, String p) async {
    await t.enterText(find.byType(TextFormField).at(0), u);
    await t.enterText(find.byType(TextFormField).at(1), p);
    await t.runAsync(() async {
      await t.tap(find.text('ورود'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
  }

  testWidgets('saved login pre-fills the form and the box is ticked', (t) async {
    await pumpLogin(t, MemoryCredentialStore(const SavedLogin('admin', 'admin123')));
    expect(fieldText(t, 0), 'admin');
    expect(fieldText(t, 1), 'admin123');
    expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isTrue);
  });

  testWidgets('nothing saved: empty form, unticked', (t) async {
    await pumpLogin(t, MemoryCredentialStore());
    expect(fieldText(t, 0), isEmpty);
    expect(t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
  });

  testWidgets('a successful login with the box ticked saves it', (t) async {
    final store = MemoryCredentialStore();
    await pumpLogin(t, store);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await submit(t, ' admin ', 'admin123');
    expect(auth.isLoggedIn, isTrue);
    expect(store.saved?.username, 'admin'); // trimmed
    expect(store.saved?.password, 'admin123');
  });

  testWidgets('a failed login saves nothing', (t) async {
    final store = MemoryCredentialStore();
    await pumpLogin(t, store);
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await submit(t, 'admin', 'wrong');
    expect(auth.isLoggedIn, isFalse);
    expect(store.saved, isNull);
    expect(find.text('نام کاربری یا رمز عبور اشتباه است'), findsOneWidget);
  });

  testWidgets('unticking the box and logging in forgets the saved login', (t) async {
    final store = MemoryCredentialStore(const SavedLogin('admin', 'admin123'));
    await pumpLogin(t, store);
    await t.tap(find.byType(CheckboxListTile)); // untick
    await t.pump();
    await submit(t, 'admin', 'admin123');
    expect(auth.isLoggedIn, isTrue);
    expect(store.saved, isNull);
  });
}
