import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'providers/app_state.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/db_status.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = DatabaseService.instance;
  final auth = AuthService(db);

  String? startupError;
  try {
    await db.init(); // opens the local file, tries the share, starts the watcher
    await auth.seedAdminIfEmpty();
  } catch (e) {
    startupError = '$e';
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DbStatus>(create: (_) => DbStatus(db)),
        ChangeNotifierProvider<AuthService>.value(value: auth),
        ChangeNotifierProvider<AppState>(create: (_) => AppState(db, auth)),
      ],
      child: BudgetApp(startupError: startupError),
    ),
  );
}

class BudgetApp extends StatelessWidget {
  const BudgetApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.companyName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: startupError != null
          ? _StartupErrorScreen(message: startupError!)
          : const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.watch<AuthService>().isLoggedIn;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: loggedIn
          ? const HomeShell(key: ValueKey('home'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 12),
                  const Text('اتصال به پایگاه داده ممکن نشد',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text('مسیر: ${AppConfig.localDbPath}',
                      textDirection: TextDirection.ltr),
                  const SizedBox(height: 10),
                  SelectableText(message, textDirection: TextDirection.ltr),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
