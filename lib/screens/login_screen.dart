import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_service.dart';
import '../services/credential_store.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  /// Pre-fill the form with the login remembered on this PC (if any).
  Future<void> _loadSaved() async {
    final saved = await context.read<CredentialStore>().load();
    if (saved == null || !mounted) return;
    setState(() {
      _user.text = saved.username;
      _pass.text = saved.password;
      _remember = true;
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final store = context.read<CredentialStore>();
    final username = _user.text.trim(), password = _pass.text, remember = _remember;
    try {
      final ok = await context.read<AuthService>().login(username, password);
      if (ok) {
        // Only a login that worked is remembered; unchecking forgets it.
        if (remember) {
          await store.save(username, password);
        } else {
          await store.clear();
        }
      } else if (mounted) {
        setState(() => _error = 'نام کاربری یا رمز عبور اشتباه است');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'خطا در اتصال به پایگاه داده: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [scheme.primary, scheme.primary.withValues(alpha: 0.55)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black38,
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            size: 52, color: scheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          AppConfig.companyName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text('ورود به سامانه',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).hintColor)),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _user,
                          autofocus: true,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'نام کاربری',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'نام کاربری را وارد کنید'
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pass,
                          obscureText: _obscure,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'رمز عبور',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v ?? '').isEmpty
                              ? 'رمز عبور را وارد کنید'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 6),
                        CheckboxListTile(
                          value: _remember,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _remember = v ?? false),
                          title: const Text('ذخیره نام کاربری و رمز عبور'),
                          subtitle: const Text(
                              'روی همین رایانه و فقط برای حساب ویندوز شما ذخیره می‌شود',
                              style: TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!,
                              style: TextStyle(color: scheme.error),
                              textAlign: TextAlign.center),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('ورود'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
