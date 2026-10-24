import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

/// Shown above every screen while the shared DB is unreachable or changes are waiting to be sent.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.user == null) return const SizedBox.shrink();
    final n = s.pendingCount;
    String? text;
    Color color = Colors.orange.shade100;
    IconData icon = Icons.cloud_off;
    if (s.syncNotice != null) {
      text = s.syncNotice;
      color = Colors.red.shade100;
      icon = Icons.error_outline;
    } else if (!s.online) {
      text = 'ارتباط با پایگاه داده مشترک برقرار نیست. تغییرات شما روی همین رایانه ذخیره شده و پس از اتصال خودکار ارسال می‌شود'
          '${n > 0 ? ' ($n تغییر در انتظار)' : ''}';
    } else if (n > 0) {
      text = 'در حال ارسال $n تغییر به پایگاه داده مشترک...';
      icon = Icons.cloud_upload_outlined;
    }
    if (text == null) return const SizedBox.shrink();
    return Material(
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (s.syncNotice != null) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: s.clearNotice),
        ]),
      ),
    );
  }
}
