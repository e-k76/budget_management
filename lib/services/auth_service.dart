import 'dart:math';

import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../models/app_user.dart';
import 'database_service.dart';

class AuthService {
  AuthService(this._db);
  final DatabaseService _db;

  static String _hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

  /// Stored format: `salt:sha256(salt + password)`.
  static String hashPassword(String password, {String? salt}) {
    final s = salt ?? _hex(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    return '$s:${_hex(sha256.convert(utf8.encode('$s$password')).bytes)}';
  }

  static bool verify(String password, String stored) {
    final i = stored.indexOf(':');
    if (i < 0) return false;
    return hashPassword(password, salt: stored.substring(0, i)) == stored;
  }

  Future<AppUser?> login(String username, String password) async {
    final row = await _db.findUserRow(username.trim());
    if (row == null || !verify(password, row['password_hash'] as String)) return null;
    return AppUser.fromMap(row);
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) =>
      _db.insertUser(username.trim(), hashPassword(password), fullName.trim(), role);
}
