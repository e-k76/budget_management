import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _u = TextEditingController(), _p = TextEditingController();
  bool _busy = false, _hide = true;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final ok = await context.read<AppState>().login(_u.text, _p.text);
      if (!ok && mounted) toast(context, 'نام کاربری یا رمز عبور اشتباه است', error: true);
    } catch (e) {
      if (mounted) toast(context, 'خطا در اتصال به پایگاه داده: ${errText(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Icon(Icons.account_balance_wallet_rounded, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  const Text('مدیریت مالی پروژه‌ها', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 28),
                  TextField(controller: _u, autofocus: true, decoration: const InputDecoration(labelText: 'نام کاربری', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _p,
                    obscureText: _hide,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'رمز عبور',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('ورود'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
