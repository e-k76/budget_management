import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'providers/app_state.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = context.select<AppState, bool>((s) => s.user != null);
    return MaterialApp(
      title: 'مدیریت مالی پروژه‌ها',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: loggedIn ? const DashboardScreen() : const LoginScreen(),
    );
  }
}
