import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';
import '../models/models.dart';
import 'database_service.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  AuthService(this._db);

  final DatabaseService _db;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Seeds admin / admin123 when the users table is empty.
  Future<void> seedAdminIfEmpty() async {
    if (await _db.userCount() > 0) return;
    try {
      await _db.insertUser(
        username: AppConfig.defaultAdminUsername,
        passwordHash: hashPassword(AppConfig.defaultAdminPassword),
        fullName: 'مدیر سیستم',
        role: Roles.admin,
      );
    } catch (_) {
      // Another workstation seeded at the same moment (UNIQUE username).
    }
  }

  static String hashPassword(String password, {String? salt}) {
    final s = salt ?? _randomSalt();
    final digest = sha256.convert(utf8.encode('$s:$password')).toString();
    return '$s\$$digest';
  }

  static bool verifyPassword(String password, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 2) return false;
    return hashPassword(password, salt: parts[0]) == stored;
  }

  static String _randomSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  Future<bool> login(String username, String password) async {
    final row = await _db.getUserRowByUsername(username.trim());
    if (row == null ||
        !verifyPassword(password, row['password_hash'] as String)) {
      return false;
    }
    _currentUser = AppUser.fromMap(row);
    notifyListeners();
    return true;
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  void _requireAdmin() {
    if (_currentUser?.isAdmin != true) {
      throw AuthException('دسترسی کافی ندارید');
    }
  }

  Future<List<AppUser>> listUsers() {
    _requireAdmin();
    return _db.getUsers();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) async {
    _requireAdmin();
    if (username.trim().isEmpty || fullName.trim().isEmpty) {
      throw AuthException('نام کاربری و نام کامل الزامی است');
    }
    if (password.length < 6) {
      throw AuthException('رمز عبور باید حداقل ۶ کاراکتر باشد');
    }
    if (await _db.getUserRowByUsername(username.trim()) != null) {
      throw AuthException('این نام کاربری قبلاً ثبت شده است');
    }
    await _db.insertUser(
      username: username.trim(),
      passwordHash: hashPassword(password),
      fullName: fullName.trim(),
      role: role,
    );
  }

  Future<void> changeRole(AppUser user, String role) async {
    _requireAdmin();
    if (user.isAdmin && role != Roles.admin && await _db.adminCount() <= 1) {
      throw AuthException('حداقل یک مدیر سیستم باید باقی بماند');
    }
    await _db.updateUserRole(user.username, role);
    if (user.username == _currentUser?.username) {
      _currentUser = AppUser(
        id: user.id,
        username: user.username,
        fullName: user.fullName,
        role: role,
        createdAt: user.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> renameUser(AppUser user, String fullName) async {
    _requireAdmin();
    final name = fullName.trim();
    if (name.isEmpty) throw AuthException('نام کامل الزامی است');
    await _db.updateUserFullName(user.username, user.fullName, name);
    if (user.username == _currentUser?.username) {
      _currentUser = AppUser(
        id: user.id,
        username: user.username,
        fullName: name,
        role: user.role,
        createdAt: user.createdAt,
      );
      notifyListeners();
    }
  }

  Future<void> resetPassword(AppUser user, String newPassword) async {
    _requireAdmin();
    if (newPassword.length < 6) {
      throw AuthException('رمز عبور باید حداقل ۶ کاراکتر باشد');
    }
    await _db.updateUserPassword(user.username, hashPassword(newPassword));
  }

  Future<void> deleteUser(AppUser user) async {
    _requireAdmin();
    if (user.username == _currentUser?.username) {
      throw AuthException('حذف حساب کاربری فعلی ممکن نیست');
    }
    if (user.isAdmin && await _db.adminCount() <= 1) {
      throw AuthException('حداقل یک مدیر سیستم باید باقی بماند');
    }
    await _db.deleteUser(user.username);
  }
}
