import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../providers/app_state.dart';
import '../widgets/ui.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<AppUser>> _f = context.read<AppState>().users();
  void _reload() => setState(() => _f = context.read<AppState>().users());

  Future<void> _add() async {
    final u = TextEditingController(), p = TextEditingController(), n = TextEditingController();
    String role = 'viewer';
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('کاربر جدید'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: key,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: n, decoration: const InputDecoration(labelText: 'نام کامل'), validator: _req),
                const SizedBox(height: 12),
                TextFormField(controller: u, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'نام کاربری'), validator: _req),
                const SizedBox(height: 12),
                TextFormField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'رمز عبور'), validator: (v) => (v ?? '').length < 6 ? 'حداقل ۶ کاراکتر' : null),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'نقش'),
                  items: [for (final e in AppUser.roleLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => set(() => role = v!),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => key.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: const Text('ثبت')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().createUser(u.text, p.text, n.text, role);
      _reload();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  static String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'الزامی است' : null;

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().user!;
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت کاربران')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add), label: const Text('کاربر جدید')),
      body: FutureBuilder<List<AppUser>>(
        future: _f,
        builder: (c, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(24), children: [
            for (final u in snap.data!)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(u.fullName),
                  subtitle: Text('${u.username}  •  ${u.roleLabel}'),
                  trailing: u.id == me.id
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            if (!await confirm(context, 'کاربر «${u.fullName}» حذف شود؟')) return;
                            if (!context.mounted) return;
                            try {
                              await context.read<AppState>().deleteUser(u.id!);
                              _reload();
                            } catch (e) {
                              if (context.mounted) toast(context, errText(e), error: true);
                            }
                          },
                        ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
