import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../services/db_status.dart';

/// Shows whether the shared (DFS) database is connected, how many changes are
/// waiting to be sent to it, and lets the user retry the connection.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final db = context.watch<DbStatus>().db;
    final (IconData icon, Color color, String text) = db.syncing
        ? (Icons.sync_rounded, Colors.blue, 'در حال همگام‌سازی...')
        : db.online
            ? (Icons.cloud_done_rounded, const Color(0xFF22A559), 'متصل به سرور')
            : (
                Icons.cloud_off_rounded,
                const Color(0xFFF5A524),
                db.pendingCount > 0
                    ? 'آفلاین • ${db.pendingCount} تغییر در انتظار ارسال'
                    : 'آفلاین (نسخه محلی)'
              );

    final tip = StringBuffer()
      ..writeln(db.online
          ? 'سرور: ${AppConfig.remoteDbPath}'
          : 'سرور در دسترس نیست؛ داده‌ها از نسخه محلی خوانده می‌شود:')
      ..writeln(AppConfig.localDbPath);
    if (db.lastSync != null) tip.writeln('آخرین همگام‌سازی: ${db.lastSync}');
    if (!db.online && db.lastError != null) tip.writeln('خطا: ${db.lastError}');
    tip.write('برای تلاش مجدد کلیک کنید');

    final iconW = db.syncing
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: color))
        : Icon(icon, color: color, size: 22);

    return Tooltip(
      message: tip.toString(),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: db.syncing ? null : () => context.read<DbStatus>().db.syncNow(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: expanded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconW,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(text,
                          style: TextStyle(
                              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                    ),
                  ],
                )
              : iconW,
        ),
      ),
    );
  }
}
