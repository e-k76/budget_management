import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../providers/app_state.dart';
import '../services/auth_service.dart';
import '../services/db_status.dart';
import '../services/update_service.dart';
import '../services/update_status.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/update_button.dart';
import '../widgets/sync_badge.dart';
import '../widgets/status_icons.dart';
import 'all_expenses_screen.dart';
import 'all_incomes_screen.dart';
import 'dashboard_screen.dart';
import 'tickets_screen.dart';
import 'user_management_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _seenDataVersion = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<AppState>().refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateStartup());
  }

  /// On start: tell the user how the last update went, then look for a new version.
  Future<void> _updateStartup() async {
    final service = context.read<UpdateService>();
    final status = context.read<UpdateStatus>();
    final last = await service.takeLastResult();
    if (last != null && mounted) {
      showSnack(
          context,
          last.$1
              ? 'برنامه با موفقیت به نسخه ${last.$2} به‌روزرسانی شد.'
              : 'به‌روزرسانی انجام نشد: ${last.$2}',
          error: !last.$1);
    }
    await status.check();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser!;
    final db = context.watch<DbStatus>().db;
    final openTickets = context.watch<AppState>().openTickets;
    if (db.dataVersion != _seenDataVersion) {
      // The data source changed (went online/offline or finished a sync).
      _seenDataVersion = db.dataVersion;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => mounted ? context.read<AppState>().refresh(silent: true) : null);
    }

    final pages = <({String label, Widget icon, Widget page})>[
      (
        label: 'داشبورد',
        icon: const Icon(Icons.dashboard_rounded),
        page: const DashboardScreen(),
      ),
      (
        label: 'لیست هزینه‌ها',
        icon: const CashOutIcon(),
        page: const AllExpensesScreen(),
      ),
      (
        label: 'لیست درآمدها',
        icon: const Icon(Icons.account_balance_wallet_rounded),
        page: const AllIncomesScreen(),
      ),
      (
        label: user.isAdmin ? 'تیکت‌ها' : 'ثبت تیکت',
        icon: Badge(
          isLabelVisible: user.isAdmin && openTickets > 0,
          label: Text('$openTickets'),
          child: const Icon(Icons.support_agent_rounded),
        ),
        page: const TicketsPage(),
      ),
      if (user.isAdmin)
        (
          label: 'کاربران',
          icon: const Icon(Icons.manage_accounts_rounded),
          page: const UserManagementScreen(),
        ),
    ];
    final index = _index.clamp(0, pages.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: Colors.white,
            minExtendedWidth: 210,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet_rounded,
                      size: 34, color: Theme.of(context).colorScheme.primary),
                  if (wide) ...[
                    const SizedBox(height: 8),
                    const Text(AppConfig.companyName,
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UpdateButton(expanded: wide),
                      SyncBadge(expanded: wide),
                      const SizedBox(height: 8),
                      if (wide) ...[
                        Text(user.fullName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(Roles.label(user.role),
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor)),
                        const SizedBox(height: 8),
                      ],
                      IconButton(
                        tooltip: 'خروج',
                        icon: const Icon(Icons.logout_rounded),
                        onPressed: () {
                          context.read<AppState>().clear();
                          auth.logout();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            destinations: [
              for (final p in pages)
                NavigationRailDestination(
                    icon: p.icon, label: Text(p.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('_'),
              child: pages[index].page,
            ),
          ),
        ],
      ),
    );
  }
}
