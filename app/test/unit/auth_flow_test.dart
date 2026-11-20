import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/core/api/api_client.dart';
import 'package:sensor_dashboard/features/auth/auth_controller.dart';
import 'package:sensor_dashboard/features/auth/models/session.dart';
import 'package:sensor_dashboard/features/auth/token_store.dart';

import '../helpers/fake_api.dart';

void main() {
  late FakeApi fake;
  late ApiClient api;
  late MemoryTokenStore store;
  late DateTime now;
  AuthController controller() => AuthController(store: store, login: api.login, clock: () => now);

  setUp(() {
    now = DateTime.utc(2026, 11, 18, 12);
    fake = FakeApi(now: now);
    store = MemoryTokenStore();
    api = ApiClient(baseUrl: () => 'http://127.0.0.1:3000', token: () => null, client: fake.client);
  });

  test('successful sign-in stores the session and exposes the role', () async {
    final auth = controller();
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);

    expect(await auth.signIn(' viewer@example.com ', 'viewer-pass'), isTrue);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.session!.role, UserRole.viewer);
    expect(auth.isAdmin, isFalse);
    expect(store.session!.token, FakeApi.viewerToken);
    expect(fake.requests.single.url.toString(), 'http://127.0.0.1:3000/auth/login');
    auth.dispose();
  });

  test('wrong password shows the server message and stays signed out', () async {
    final auth = controller();
    await auth.restore();
    expect(await auth.signIn('viewer@example.com', 'nope'), isFalse);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.error, 'Wrong email or password.');
    expect(store.session, isNull);
  });

  test('unreachable server gives a friendly message', () async {
    fake.offline = true;
    final auth = controller();
    await auth.restore();
    expect(await auth.signIn('viewer@example.com', 'viewer-pass'), isFalse);
    expect(auth.error, contains("Can't reach the server"));
    expect(auth.error, isNot(contains('Exception')));
  });

  test('restores a valid stored session; discards an expired one', () async {
    store.session = FakeApi.session(UserRole.admin, expiresAt: now.add(const Duration(minutes: 5)));
    final a = controller();
    await a.restore();
    expect(a.isSignedIn, isTrue);
    expect(a.isAdmin, isTrue);
    a.dispose();

    store.session = FakeApi.session(
      UserRole.admin,
      expiresAt: now.subtract(const Duration(seconds: 1)),
    );
    final b = controller();
    await b.restore();
    expect(b.isSignedIn, isFalse);
    expect(store.session, isNull);
  });

  test('signs out automatically when the token expires', () {
    fakeAsync((async) {
      final auth = controller();
      auth.restore();
      auth.signIn('admin@example.com', 'admin-pass');
      async.flushMicrotasks();
      expect(auth.isSignedIn, isTrue);

      async.elapse(const Duration(minutes: 29, seconds: 59));
      expect(auth.isSignedIn, isTrue);
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(auth.isSignedIn, isFalse);
      expect(auth.notice, AuthController.expiredMessage);
      expect(store.session, isNull);
    });
  });

  test('checkExpiry on resume catches a delayed timer', () async {
    final auth = controller();
    store.session = FakeApi.session(
      UserRole.viewer,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    await auth.restore();
    now = now.add(const Duration(minutes: 2));
    auth.checkExpiry();
    await Future<void>.delayed(Duration.zero);
    expect(auth.isSignedIn, isFalse);
    expect(auth.notice, AuthController.expiredMessage);
  });

  test('a 401 from the API signs the user out', () async {
    late AuthController auth;
    final authed = ApiClient(
      baseUrl: () => 'http://127.0.0.1:3000',
      token: () => 'revoked',
      client: fake.client,
      onUnauthorized: (m) => auth.handleUnauthorized(m),
    );
    store.session = FakeApi.session(
      UserRole.viewer,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    auth = controller();
    await auth.restore();
    await expectLater(authed.getThresholds(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    expect(auth.isSignedIn, isFalse);
    auth.dispose();
  });

  test('viewer gets 403 when changing thresholds; admin succeeds', () async {
    ApiClient as(String token) =>
        ApiClient(baseUrl: () => 'http://127.0.0.1:3000', token: () => token, client: fake.client);
    final t = await as(FakeApi.adminToken).getThresholds();
    await expectLater(
      as(FakeApi.viewerToken).putThresholds(t),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.forbidden)),
    );
    await as(FakeApi.adminToken).putThresholds(t);
  });

  test('Session JSON round trip and malformed login response', () {
    final s = FakeApi.session(UserRole.admin, expiresAt: now);
    final back = Session.tryFromJson(s.toJson())!;
    expect(
      [back.token, back.email, back.role, back.expiresAt],
      [s.token, s.email, s.role, s.expiresAt],
    );
    expect(Session.tryFromJson({'token': 'x'}), isNull);
    expect(() => Session.fromLoginJson({'token': 'x', 'user': {}}), throwsFormatException);
  });
}
