import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/session.dart';

/// Where the session token is kept between app launches.
abstract interface class TokenStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

/// Android Keystore-backed storage via flutter_secure_storage.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'auth.session';
  final FlutterSecureStorage _storage;

  @override
  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return Session.tryFromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      // Unreadable (for example after a keystore reset): treat as signed out.
      debugPrint('Stored session unreadable: ${e.runtimeType}');
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } catch (e) {
      debugPrint('Could not clear stored session: ${e.runtimeType}');
    }
  }
}

/// For tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.session]);
  Session? session;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session s) async => session = s;

  @override
  Future<void> clear() async => session = null;
}
