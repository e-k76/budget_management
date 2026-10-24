import 'dart:io';

class AppConfig {
  AppConfig._();

  /// Shared database on the DFS file server (UNC path, raw string).
  static const String remoteDbPath =
      r'\\dfs\Moasese Samavat\مدیریت فنی و مهندسی\Cost\projects.db';

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
