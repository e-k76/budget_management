import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedLogin {
  const SavedLogin(this.username, this.password);
  final String username;
  final String password;
}

/// Where the "remember me" login is kept. Failures never break logging in:
/// a store that can't be read or written simply behaves as "nothing saved".
abstract class CredentialStore {
  Future<SavedLogin?> load();
  Future<void> save(String username, String password);
  Future<void> clear();
}

/// Windows: the values are encrypted with the signed-in Windows user's key
/// (DPAPI), so they are not readable as plain text and are only usable by
/// that Windows account on that PC.
class SecureCredentialStore implements CredentialStore {
  const SecureCredentialStore();

  static const _storage = FlutterSecureStorage();
  static const _userKey = 'login_username';
  static const _passKey = 'login_password';

  @override
  Future<SavedLogin?> load() async {
    try {
      final u = await _storage.read(key: _userKey);
      final p = await _storage.read(key: _passKey);
      if (u == null || u.isEmpty || p == null || p.isEmpty) return null;
      return SavedLogin(u, p);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String username, String password) async {
    try {
      await _storage.write(key: _userKey, value: username);
      await _storage.write(key: _passKey, value: password);
    } catch (_) {}
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _passKey);
    } catch (_) {}
  }
}

/// For tests.
class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore([this.saved]);
  SavedLogin? saved;

  @override
  Future<SavedLogin?> load() async => saved;

  @override
  Future<void> save(String username, String password) async =>
      saved = SavedLogin(username, password);

  @override
  Future<void> clear() async => saved = null;
}
