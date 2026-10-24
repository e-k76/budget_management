class AppUser {
  final int? id;
  final String username;
  final String fullName;
  final String role; // admin | manager | viewer

  const AppUser({this.id, required this.username, required this.fullName, required this.role});

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int?,
        username: m['username'] as String,
        fullName: m['full_name'] as String,
        role: m['role'] as String,
      );

  bool get isAdmin => role == 'admin';
  bool get canEdit => role == 'admin' || role == 'manager';

  static const roleLabels = {'admin': 'مدیر سیستم', 'manager': 'مدیر مالی', 'viewer': 'مشاهده‌گر'};
  String get roleLabel => roleLabels[role] ?? role;
}
