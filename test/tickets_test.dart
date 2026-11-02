import 'dart:io';

import 'package:budget_management/core/app_config.dart';
import 'package:budget_management/models/models.dart';
import 'package:budget_management/providers/app_state.dart';
import 'package:budget_management/screens/tickets_screen.dart';
import 'package:budget_management/services/auth_service.dart';
import 'package:budget_management/services/database_service.dart';
import 'package:budget_management/services/db_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tmp;
  late DatabaseService db;
  late AuthService auth;
  late AppState state;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bm_tickets');
    db = DatabaseService.instance
      ..localPathOverride = '${tmp.path}/local/projects.db'
      ..remotePathOverride = '${tmp.path}/remote/projects.db'
      ..remoteEnabled = false
      ..simulateUnreachable = false;
    await db.init();
    auth = AuthService(db);
    await auth.seedAdminIfEmpty();
    state = AppState(db, auth);
  });

  var cleanedInTest = false; // widget tests clean up in real time (see closeDb)

  tearDown(() async {
    if (cleanedInTest) {
      cleanedInTest = false;
      return;
    }
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> loginAs(String username) async {
    state.clear(); // what the logout button does
    auth.logout();
    expect(await auth.login(username, 'pw-$username'), isTrue, reason: username);
  }

  Future<void> makeUsers() async {
    expect(await auth.login('admin', 'admin123'), isTrue);
    await auth.createUser(username: 'ali', password: 'pw-ali', fullName: 'علی مدیر مالی', role: Roles.manager);
    await auth.createUser(username: 'sara', password: 'pw-sara', fullName: 'سارا', role: Roles.viewer);
  }

  group('database', () {
    test('insert, list (newest first), status, delete, open count', () async {
      await db.insertTicket(kind: 'bug', subject: 'اولی', message: 'متن ۱', createdBy: 'ali', createdByName: 'علی');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await db.insertTicket(kind: 'suggestion', subject: 'دومی', message: 'متن ۲', createdBy: 'sara', createdByName: 'سارا');
      var list = await db.getTickets();
      expect(list.map((t) => t.subject), ['دومی', 'اولی']);
      expect(list.first.status, Ticket.open);
      expect(list.first.createdByName, 'سارا');
      expect(list.first.kindLabel, 'پیشنهاد / قابلیت جدید');
      expect(list.map((t) => t.uid).toSet().length, 2);
      expect(await db.countOpenTickets(), 2);

      await db.setTicketStatus(list.last.uid, Ticket.done, 'مدیر');
      list = await db.getTickets();
      final done = list.firstWhere((t) => t.subject == 'اولی');
      expect(done.isDone, isTrue);
      expect(done.updatedBy, 'مدیر');
      expect(done.updatedAt, isNotNull);
      expect(await db.countOpenTickets(), 1);

      await db.deleteTicket(done.uid);
      expect((await db.getTickets()).map((t) => t.subject), ['دومی']);
    });

    test('tickets land in the shared DB too, and an offline ticket is sent once online', () async {
      db.remoteEnabled = true;
      await db.init(waitForConnection: true); // share folder missing -> offline
      expect(db.online, isFalse);
      final queued = db.pendingCount; // e.g. the seeded admin user is waiting too
      await db.insertTicket(kind: 'bug', subject: 'آفلاین', message: 'x', createdBy: 'u', createdByName: 'U');
      expect(db.pendingCount, queued + 1);
      expect(await db.countOpenTickets(), 1); // visible locally right away

      await Directory('${tmp.path}/remote').create();
      await db.tick();
      expect(db.online, isTrue);
      expect(db.pendingCount, 0);

      Future<int> remoteCount() async {
        final d = await databaseFactoryFfi.openDatabase('${tmp.path}/remote/projects.db',
            options: OpenDatabaseOptions(singleInstance: false));
        try {
          return (await d.rawQuery('SELECT COUNT(*) c FROM tickets')).first['c'] as int;
        } finally {
          await d.close();
        }
      }

      expect(await remoteCount(), 1);
      // while connected, a new ticket is written to the share immediately
      await db.insertTicket(kind: 'other', subject: 'آنلاین', message: 'y', createdBy: 'u', createdByName: 'U');
      expect(await remoteCount(), 2);
      expect(db.pendingCount, 0);
    });

    test('an existing shared DB from before tickets gets the table (and sync triggers) on connect', () async {
      await Directory('${tmp.path}/remote').create();
      // what an older version left on the share: schema version 2, no tickets table
      final old = await databaseFactoryFfi.openDatabase('${tmp.path}/remote/projects.db',
          options: OpenDatabaseOptions(singleInstance: false));
      await old.execute('PRAGMA user_version = 2');
      await old.close();

      db.remoteEnabled = true;
      await db.init(waitForConnection: true);
      expect(db.online, isTrue, reason: db.lastError);
      await db.insertTicket(kind: 'bug', subject: 's', message: 'm', createdBy: 'u', createdByName: 'U');

      final d = await databaseFactoryFfi.openDatabase('${tmp.path}/remote/projects.db',
          options: OpenDatabaseOptions(singleInstance: false));
      final tables = (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']);
      final triggers = (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'trg_sync_tickets_%'"));
      final version = (await d.rawQuery('PRAGMA user_version')).first.values.first;
      final tickets = await d.query('tickets');
      await d.close();
      expect(tables, contains('tickets'));
      expect(triggers.length, 3); // other PCs notice new tickets like any other change
      expect(version, 3);
      expect(tickets.length, 1);
    });
  });

  group('who can do what', () {
    test('every role can send a ticket; only admins can read or manage them', () async {
      await makeUsers();
      for (final who in ['ali', 'sara', 'admin']) {
        if (who == 'admin') {
          auth.logout();
          expect(await auth.login('admin', 'admin123'), isTrue);
        } else {
          await loginAs(who);
        }
        await state.submitTicket(kind: 'bug', subject: 'از $who', message: 'متن');
      }
      // manager and viewer cannot read / change / delete
      for (final who in ['ali', 'sara']) {
        await loginAs(who);
        await expectLater(state.tickets(), throwsA(isA<AuthException>()), reason: who);
        final any = (await db.getTickets()).first;
        await expectLater(state.setTicketStatus(any, Ticket.done), throwsA(isA<AuthException>()), reason: who);
        await expectLater(state.deleteTicket(any), throwsA(isA<AuthException>()), reason: who);
        expect(state.openTickets, 0, reason: 'no badge for $who');
      }
      // the admin sees all three, with who sent them
      auth.logout();
      await auth.login('admin', 'admin123');
      final all = await state.tickets();
      expect(all.map((t) => t.createdBy).toSet(), {'ali', 'sara', 'admin'});
      expect(all.firstWhere((t) => t.createdBy == 'ali').createdByName, 'علی مدیر مالی');
      await state.refresh();
      expect(state.openTickets, 3);
      await state.setTicketStatus(all.first, Ticket.done);
      expect(state.openTickets, 2);
      await state.deleteTicket(all.last);
      expect((await state.tickets()).length, 2);
      expect(state.openTickets, 1);
    });

    test('validation', () async {
      await auth.login('admin', 'admin123');
      await expectLater(state.submitTicket(kind: 'bug', subject: '  ', message: 'x'), throwsA(isA<AuthException>()));
      await expectLater(state.submitTicket(kind: 'bug', subject: 'x', message: ' '), throwsA(isA<AuthException>()));
      await expectLater(state.submitTicket(kind: 'nope', subject: 'x', message: 'x'), throwsA(isA<AuthException>()));
      await expectLater(state.submitTicket(kind: 'bug', subject: 'x' * 121, message: 'x'), throwsA(isA<AuthException>()));
      await expectLater(state.submitTicket(kind: 'bug', subject: 'x', message: 'x' * 4001), throwsA(isA<AuthException>()));
      await state.submitTicket(kind: 'bug', subject: '  با فاصله  ', message: ' متن ');
      final t = (await state.tickets()).single;
      expect(t.subject, 'با فاصله');
      expect(t.message, 'متن');
      await expectLater(state.setTicketStatus(t, 'weird'), throwsA(isA<AuthException>()));
    });
  });

  group('screens', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 4; i++) {
        await t.pump();
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      }
      await t.pumpAndSettle();
    }

    Future<void> tapAsync(WidgetTester t, Finder f) async {
      await t.runAsync(() async {
        await t.tap(f);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await settle(t);
    }

    /// The DB talks to a background isolate, so it must be closed in real time (the
    /// widget-test zone never runs those callbacks once the test body is over).
    Future<void> closeDb(WidgetTester t) async {
      await t.pumpWidget(const SizedBox()); // dispose the screen first
      await t.runAsync(() async {
        await db.close().timeout(const Duration(seconds: 10));
        await tmp.delete(recursive: true);
      });
      cleanedInTest = true;
    }

    Future<void> pumpPage(WidgetTester t) async {
      t.view.physicalSize = const Size(1800, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<DbStatus>(create: (_) => DbStatus(db)),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<AppState>.value(value: state),
        ],
        child: MaterialApp(
          builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
          home: const Scaffold(body: TicketsPage()),
        ),
      ));
      await settle(t);
    }

    testWidgets('a normal user sees only the form, and sending stores the ticket', (t) async {
      await t.runAsync(() async {
        await makeUsers();
        await loginAs('sara');
      });
      await pumpPage(t);
      expect(find.text('ثبت تیکت'), findsOneWidget);
      expect(find.text('ارسال تیکت'), findsOneWidget);
      expect(find.text('تیکت‌ها'), findsNothing); // no list for non-admins
      expect(find.text('ردیف'), findsNothing); // no ticket table

      // empty form: validation, nothing stored
      await t.tap(find.text('ارسال تیکت'));
      await t.pump();
      expect(find.text('موضوع را وارد کنید'), findsOneWidget);
      expect(find.text('متن تیکت را وارد کنید'), findsOneWidget);

      await t.enterText(find.byType(TextFormField).at(0), 'چاپ کار نمی‌کند');
      await t.enterText(find.byType(TextFormField).at(1), 'وقتی روی پرینت می‌زنم صفحه سفید می‌شود');
      await tapAsync(t, find.text('ارسال تیکت'));

      final stored = await t.runAsync(() => db.getTickets());
      expect(stored!.single.subject, 'چاپ کار نمی‌کند');
      expect(stored.single.createdBy, 'sara');
      expect(stored.single.createdByName, 'سارا');
      // the form is cleared and the ticket is NOT shown back to the sender
      expect(find.text('چاپ کار نمی‌کند'), findsNothing);
      expect(t.takeException(), isNull);
      await closeDb(t);
    });

    testWidgets('the admin sees the list, opens a ticket, changes its status and deletes it', (t) async {
      await t.runAsync(() async {
        await makeUsers();
        await loginAs('ali');
        await state.submitTicket(kind: 'bug', subject: 'موضوع اول', message: 'متن کامل تیکت اول');
        await loginAs('sara');
        await state.submitTicket(kind: 'suggestion', subject: 'موضوع دوم', message: 'متن دوم');
        auth.logout();
        await auth.login('admin', 'admin123');
        await state.refresh();
      });
      await pumpPage(t);
      expect(find.text('تیکت‌ها'), findsOneWidget);
      expect(find.text('موضوع اول'), findsOneWidget);
      expect(find.text('موضوع دوم'), findsOneWidget);
      expect(find.text('علی مدیر مالی'), findsOneWidget);
      expect(find.text('جدید'), findsWidgets);

      // search narrows the list
      await t.enterText(find.byType(TextField).first, 'اول');
      await t.pump();
      expect(find.text('موضوع دوم'), findsNothing);
      await t.enterText(find.byType(TextField).first, '');
      await t.pump();

      // open the first ticket: the full text is shown, mark it done
      await t.tap(find.text('موضوع اول'));
      await t.pumpAndSettle();
      expect(find.text('متن کامل تیکت اول'), findsOneWidget);
      await tapAsync(t, find.text('علامت‌گذاری: انجام شد'));
      final afterDone = await t.runAsync(() => db.getTickets());
      expect(afterDone!.firstWhere((x) => x.subject == 'موضوع اول').isDone, isTrue);
      expect(find.text('انجام شد'), findsWidgets); // chip in the list
      expect(state.openTickets, 1);

      // filter by status
      await t.tap(find.byType(DropdownButtonFormField<String?>));
      await t.pumpAndSettle();
      await t.tap(find.text('جدید').last);
      await t.pumpAndSettle();
      expect(find.text('موضوع اول'), findsNothing);
      expect(find.text('موضوع دوم'), findsOneWidget);

      // delete the remaining visible one (asks first)
      await t.tap(find.byTooltip('حذف').first);
      await t.pumpAndSettle();
      await tapAsync(t, find.text('حذف').last);
      final left = await t.runAsync(() => db.getTickets());
      expect(left!.map((x) => x.subject), ['موضوع اول']);
      expect(t.takeException(), isNull);
      await closeDb(t);
    });
  });
}
