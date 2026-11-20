import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import 'models/session.dart';
import 'token_store.dart';

enum AuthStatus { restoring, signedOut, signedIn }

/// Sign in / sign out, token persistence and automatic sign-out on expiry.
class AuthController extends ChangeNotifier {
  AuthController({
    required TokenStore store,
    required Future<Session> Function(String email, String password) login,
    DateTime Function()? clock,
  }) : _store = store,
       _login = login,
       _clock = clock ?? DateTime.now;

  static const String expiredMessage = 'Your session expired. Please sign in again.';

  final TokenStore _store;
  final Future<Session> Function(String, String) _login;
  final DateTime Function() _clock;

  AuthStatus _status = AuthStatus.restoring;
  Session? _session;
  bool _busy = false;
  String? _error;
  String? _notice;
  Timer? _expiryTimer;

  AuthStatus get status => _status;
  Session? get session => _session;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  bool get isAdmin => _session?.isAdmin ?? false;
  bool get isBusy => _busy;

  /// Last sign-in error (friendly text).
  String? get error => _error;

  /// Why the user was signed out (for example "session expired").
  String? get notice => _notice;

  /// Loads a stored session. Expired sessions are discarded.
  Future<void> restore() async {
    final s = await _store.read();
    if (s != null && !s.isExpiredAt(_clock())) {
      _setSignedIn(s);
    } else {
      if (s != null) await _store.clear();
      _status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  /// Returns true on success; otherwise [error] holds a friendly message.
  Future<bool> signIn(String email, String password) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final s = await _login(email, password);
      await _store.write(s);
      _setSignedIn(s);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      debugPrint('Sign-in failed: ${e.runtimeType}');
      _error = "Couldn't sign in. Try again.";
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut({String? notice}) async {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    final wasSignedIn = _status != AuthStatus.signedOut;
    _session = null;
    _status = AuthStatus.signedOut;
    _notice = notice;
    _error = null;
    await _store.clear();
    if (wasSignedIn || notice != null) notifyListeners();
  }

  /// Called when the API rejects the token (expired or revoked).
  void handleUnauthorized(String message) {
    if (!isSignedIn) return;
    signOut(notice: message.contains('expired') ? expiredMessage : 'Please sign in again.');
  }

  /// Timers can be delayed while the app is in the background; check on resume.
  void checkExpiry() {
    final s = _session;
    if (s != null && s.isExpiredAt(_clock())) signOut(notice: expiredMessage);
  }

  void _setSignedIn(Session s) {
    _session = s;
    _status = AuthStatus.signedIn;
    _expiryTimer?.cancel();
    final left = s.expiresAt.difference(_clock());
    _expiryTimer = Timer(
      left.isNegative ? Duration.zero : left,
      () => signOut(notice: expiredMessage),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }
}
