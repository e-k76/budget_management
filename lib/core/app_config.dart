import 'dart:io';

class AppConfig {
  AppConfig._();

  /// Shared database on the DFS file server (UNC path, raw string). It lives in
  /// the dedicated `DB` folder (the old `Cost\projects.db` file is no longer used).
  static const String defaultRemoteDbPath =
      r'\\dfs\Moasese Samavat\مدیریت فنی و مهندسی\Cost\DB\projects.db';

  /// The path actually used: [defaultRemoteDbPath] unless this PC has a
  /// `server_path.txt` (see [loadOverrides]).
  static String remoteDbPath = defaultRemoteDbPath;

  /// Optional per-PC override so the server location can be changed without
  /// rebuilding: put the full path to `projects.db` on the first line of
  /// `Desktop\project_manage\server_path.txt` (lines starting with # are ignored).
  static void loadOverrides({String? file}) {
    try {
      final f = File(file ?? '${Platform.environment['USERPROFILE']}\\Desktop\\project_manage\\server_path.txt');
      if (!f.existsSync()) return;
      for (final line in f.readAsLinesSync()) {
        final t = line.trim();
        if (t.isNotEmpty && !t.startsWith('#')) {
          remoteDbPath = t;
          return;
        }
      }
    } catch (_) {
      // unreadable override file: keep the default
    }
  }

  /// This machine's own copy; always written, and the only one used while
  /// the share is unreachable.
  static final String localDbPath =
      '${Platform.environment['USERPROFILE']}\\Desktop\\project_manage\\projects.db';

  static const String companyName = 'مدیریت مالی پروژه‌ها';
  static const String fontFamily = 'Dana';

  static const String defaultAdminUsername = 'admin';
  static const String defaultAdminPassword = 'admin123';
}

class Roles {
  Roles._();

  static const admin = 'admin';
  static const manager = 'manager';
  static const viewer = 'viewer';

  static const all = [admin, manager, viewer];

  static String label(String role) {
    switch (role) {
      case admin:
        return 'مدیر سیستم';
      case manager:
        return 'مدیر مالی';
      default:
        return 'مشاهده‌گر';
    }
  }
}
