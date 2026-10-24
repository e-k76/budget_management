import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../widgets/ui_helpers.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await context.read<AuthService>().listUsers();
      if (mounted) setState(() => _users = u);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  Future<void> _addUser() async {
    final r = await showDialog<_NewUser>(
        context: context, builder: (_) => const _NewUserDialog());
    if (r == null || !mounted) return;
    final auth = context.read<AuthService>();
    _run(() => auth.createUser(
        username: r.username,
        password: r.password,
        fullName: r.fullName,
        role: r.role));
  }

  Future<void> _rename(AppUser u) async {
    final c = TextEditingController(text: u.fullName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('نام کامل ${u.username}'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'نام کامل'),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('ثبت')),
        ],
      ),
    );
    c.dispose();
    if (name == null || !mounted) return;
    final auth = context.read<AuthService>();
    _run(() async {
      await auth.renameUser(u, name);
      if (mounted) {
        showSnack(context, 'نام کامل تغییر کرد و در سوابق تایید/ثبت هم اعمال شد');
      }
    });
  }

  Future<void> _resetPassword(AppUser u) async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رمز جدید برای ${u.username}'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: c,
            obscureText: true,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'رمز عبور جدید'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('ثبت')),
        ],
      ),
    );
    c.dispose();
    if (pw == null || !mounted) return;
    final auth = context.read<AuthService>();
    _run(() async {
      await auth.resetPassword(u, pw);
      if (mounted) showSnack(context, 'رمز عبور تغییر کرد');
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final me = auth.currentUser!;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('مدیریت کاربران',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                onPressed: _addUser,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('کاربر جدید'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'کاربران سامانه',
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
                : ScrollableTable(
                    table: DataTable(
                      columns: const [
                        DataColumn(label: Text('ردیف')),
                        DataColumn(label: Text('نام کاربری')),
                        DataColumn(label: Text('نام کامل')),
                        DataColumn(label: Text('نقش')),
                        DataColumn(label: Text('عملیات')),
                      ],
                      rows: [
                        for (var i = 0; i < _users.length; i++)
                          DataRow(cells: [
                            DataCell(Text('${i + 1}')),
                            DataCell(Text(_users[i].username)),
                            DataCell(Text(_users[i].fullName)),
                            DataCell(DropdownButton<String>(
                              value: _users[i].role,
                              underline: const SizedBox.shrink(),
                              items: [
                                for (final r in Roles.all)
                                  DropdownMenuItem(
                                      value: r, child: Text(Roles.label(r))),
                              ],
                              onChanged: (r) {
                                if (r == null || r == _users[i].role) return;
                                _run(() => auth.changeRole(_users[i], r));
                              },
                            )),
                            DataCell(Row(children: [
                              IconButton(
                                tooltip: 'ویرایش نام کامل',
                                icon: const Icon(Icons.badge_outlined, size: 20),
                                onPressed: () => _rename(_users[i]),
                              ),
                              IconButton(
                                tooltip: 'تغییر رمز عبور',
                                icon: const Icon(Icons.key_rounded, size: 20),
                                onPressed: () => _resetPassword(_users[i]),
                              ),
                              if (_users[i].username != me.username)
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: Icon(Icons.delete_outline,
                                      size: 20,
                                      color: Theme.of(context).colorScheme.error),
                                  onPressed: () async {
                                    final ok = await confirmDialog(context,
                                        title: 'حذف کاربر',
                                        message:
                                            'کاربر «${_users[i].username}» حذف شود؟');
                                    if (ok) {
                                      _run(() => auth.deleteUser(_users[i]));
                                    }
                                  },
                                ),
                            ])),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NewUser {
  final String username, password, fullName, role;
  _NewUser(this.username, this.password, this.fullName, this.role);
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();
  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  String _role = Roles.viewer;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? 'این فیلد الزامی است' : null;
    return AlertDialog(
      title: const Text('کاربر جدید'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullName,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'نام کامل'),
                  validator: required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'نام کاربری'),
                  validator: required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                      labelText: 'رمز عبور (حداقل ۶ کاراکتر)'),
                  validator: (v) =>
                      (v ?? '').length < 6 ? 'حداقل ۶ کاراکتر' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'نقش'),
                  items: [
                    for (final r in Roles.all)
                      DropdownMenuItem(value: r, child: Text(Roles.label(r))),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
                context,
                _NewUser(_username.text, _password.text, _fullName.text, _role));
          },
          child: const Text('ایجاد'),
        ),
      ],
    );
  }
}
