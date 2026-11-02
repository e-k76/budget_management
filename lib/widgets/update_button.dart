import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../services/update_service.dart';
import '../services/update_status.dart';

/// Menu button: «به‌روزرسانی برنامه», with a dot when a newer version is waiting.
class UpdateButton extends StatelessWidget {
  const UpdateButton({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<UpdateStatus>();
    final has = s.hasUpdate;
    final color = has ? const Color(0xFFE8590C) : Theme.of(context).hintColor;
    final icon = Badge(
      isLabelVisible: has,
      smallSize: 9,
      child: Icon(Icons.system_update_alt_rounded, color: color, size: 22),
    );
    return Tooltip(
      message: has ? 'نسخه جدید برنامه آماده نصب است' : 'بررسی به‌روزرسانی برنامه',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showUpdateDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: expanded
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  icon,
                  const SizedBox(width: 8),
                  Text(has ? 'نسخه جدید موجود است' : 'به‌روزرسانی برنامه',
                      style: TextStyle(
                          color: color,
                          fontWeight: has ? FontWeight.w700 : FontWeight.w500)),
                ])
              : icon,
        ),
      ),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context) {
  context.read<UpdateStatus>().check(); // always look again when opened
  return showDialog<void>(context: context, builder: (_) => const _UpdateDialog());
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog();

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _copying = false;
  bool _restarting = false;
  int _done = 0, _total = 0;
  String? _installError;

  Future<void> _install(UpdateInfo info) async {
    final service = context.read<UpdateService>();
    setState(() {
      _copying = true;
      _installError = null;
    });
    try {
      final staging = await service.stage(info, onProgress: (d, t) {
        if (mounted) {
          setState(() {
            _done = d;
            _total = t;
          });
        }
      });
      if (mounted) setState(() => _restarting = true);
      await service.apply(staging, info);
      // Close the databases cleanly, then leave: the helper replaces the files
      // and starts the new version.
      try {
        await DatabaseService.instance.close().timeout(const Duration(seconds: 5));
      } catch (_) {}
      exit(0);
    } on UpdateException catch (e) {
      if (mounted) setState(() => _installError = e.message);
    } catch (e) {
      if (mounted) setState(() => _installError = '$e');
    }
    if (mounted) setState(() => _copying = false);
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<UpdateStatus>();
    final service = context.read<UpdateService>();
    final info = status.info;
    final err = _installError ?? status.error;

    Widget body;
    List<Widget> actions;
    if (_restarting) {
      body = const Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        SizedBox(width: 14),
        Expanded(child: Text('برنامه برای نصب بسته می‌شود و خودکار دوباره باز می‌شود...')),
      ]);
      actions = const [];
    } else if (_copying) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('در حال دریافت فایل‌ها از سرور...'),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
        const SizedBox(height: 6),
        Text(_total == 0 ? '' : '$_done از $_total فایل',
            style: TextStyle(color: Theme.of(context).hintColor)),
      ]);
      actions = const [];
    } else if (status.checking) {
      body = const Row(children: [
        SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        SizedBox(width: 14),
        Text('در حال بررسی پوشه به‌روزرسانی...'),
      ]);
      actions = [TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن'))];
    } else if (err != null) {
      body = Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error));
      actions = [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        FilledButton(
            onPressed: () {
              setState(() => _installError = null);
              context.read<UpdateStatus>().check();
            },
            child: const Text('بررسی مجدد')),
      ];
    } else if (info != null && info.hasUpdate) {
      body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('نسخه فعلی: ${info.installed}      نسخه جدید: ${info.available}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (info.notes != null) ...[
          const Text('تغییرات این نسخه:'),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(child: Text(info.notes!)),
          ),
          const SizedBox(height: 10),
        ],
        Text(
            service.canSelfUpdate
                ? 'فایل‌های جدید روی پوشه برنامه همین رایانه کپی می‌شوند و برنامه دوباره باز می‌شود. اطلاعات شما تغییری نمی‌کند.'
                : 'این نسخه (اجرای توسعه) قابل به‌روزرسانی خودکار نیست.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ]);
      actions = [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بعداً')),
        FilledButton.icon(
          onPressed: service.canSelfUpdate ? () => _install(info) : null,
          icon: const Icon(Icons.system_update_alt_rounded),
          label: const Text('دریافت و نصب'),
        ),
      ];
    } else {
      body = Text(info == null
          ? 'نتیجه‌ای در دسترس نیست.'
          : 'برنامه به‌روز است (نسخه ${info.installed}).');
      actions = [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
        FilledButton(
            onPressed: () => context.read<UpdateStatus>().check(),
            child: const Text('بررسی مجدد')),
      ];
    }

    return AlertDialog(
      title: const Text('به‌روزرسانی برنامه'),
      content: SizedBox(width: 460, child: body),
      actions: actions,
    );
  }
}
