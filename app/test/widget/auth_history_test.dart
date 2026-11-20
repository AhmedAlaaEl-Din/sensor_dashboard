import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensor_dashboard/features/auth/models/session.dart';
import 'package:sensor_dashboard/features/history/history_screen.dart';

import '../helpers/app_harness.dart';

void main() {
  testWidgets('login: wrong password shows an error, right password opens the dashboard', (
    tester,
  ) async {
    final h = await pumpApp(tester, role: null);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(h.gateway.connectCalls, 0); // no live data before sign-in

    await tester.enterText(find.byKey(const Key('login-email')), 'viewer@example.com');
    await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong email or password.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login-password')), 'viewer-pass');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Sensor Dashboard'), findsOneWidget);
    expect(h.gateway.connectCalls, 1);
  });

  testWidgets('login form validates before calling the server', (tester) async {
    final h = await pumpApp(tester, role: null);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(h.api.requests, isEmpty);
  });

  testWidgets('profile shows the role; sign out returns to login and stops live data', (
    tester,
  ) async {
    final h = await pumpApp(tester, role: UserRole.admin);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('open-profile')));
    await tester.pumpAndSettle();
    expect(find.text('admin@example.com'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('profile-role')), matching: find.text('Admin')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('profile-sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(h.gateway.connected, isFalse);
  });

  testWidgets('history: loads, switches range, shows stats and exports CSV', (tester) async {
    final h = await pumpApp(tester, size: const Size(420, 1000));
    h.gateway.emitTelemetry('greenhouse', {'temperature': 22});
    await tester.pump();
    await tester.tap(find.byKey(const Key('device-card-greenhouse')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('open-history')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('History'), findsOneWidget);
    expect(find.text('19.5 °C'), findsOneWidget); // min from stats
    expect(find.text('22.9 °C'), findsOneWidget); // avg
    expect(h.api.requests.last.url.queryParameters['bucket'], '1m');

    await tester.tap(find.byKey(const Key('range-day')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(h.api.requests.last.url.queryParameters['bucket'], '15m');

    // Export downloads the 24 h CSV and offers to share it.
    // Writing the file is real I/O, so let real time pass between frames.
    await tester.tap(find.byKey(const Key('history-export')));
    for (var i = 0; i < 50 && find.byKey(const Key('export-dialog')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300)); // dialog animation
    expect(find.byKey(const Key('export-dialog')), findsOneWidget);
    expect(find.textContaining('2 rows'), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-share')));
    await tester.pumpAndSettle();
    expect(h.sharer.shared.single, endsWith('.csv'));
  });

  testWidgets('history: server down shows a friendly error with retry', (tester) async {
    final h = await pumpApp(tester);
    h.api.offline = true;
    h.services.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const HistoryScreen(deviceId: 'greenhouse')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('history-error')), findsOneWidget);
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('history: empty range shows the empty state', (tester) async {
    final h = await pumpApp(tester);
    h.api.historyBody = (uri) => {
      'deviceId': 'greenhouse',
      'bucket': '1m',
      'from': uri.queryParameters['from'],
      'to': uri.queryParameters['to'],
      'points': [],
      'stats': {},
    };
    h.services.navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const HistoryScreen(deviceId: 'greenhouse')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('history-empty')), findsOneWidget);
  });
}
