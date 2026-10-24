import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/auth_service.dart';

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
  String? _error;

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
    try {
      final ok = await context.read<AuthService>().login(_user.text, _pass.text);
      if (!ok && mounted) {
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
