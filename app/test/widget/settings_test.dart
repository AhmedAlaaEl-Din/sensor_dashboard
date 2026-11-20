import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensor_dashboard/features/auth/models/session.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';

import '../helpers/app_harness.dart';

void main() {
  Future<Harness> openSettings(WidgetTester tester, {UserRole role = UserRole.admin}) async {
    final h = await pumpApp(tester, role: role, size: const Size(420, 1600));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('admin: changing a threshold saves it on the server and applies it to alerts', (
    tester,
  ) async {
    final h = await openSettings(tester);

    await tester.enterText(find.byKey(const Key('threshold-temperature-max')), '30');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(h.api.requests.any((r) => r.method == 'PUT' && r.url.path == '/thresholds'), isTrue);
    expect(h.api.thresholds['temperature'], {'min': 5.0, 'max': 30.0});
    expect(h.repo.stored.thresholds[SensorType.temperature]!.max, 30);
    expect(h.services.alerts.thresholds[SensorType.temperature]!.max, 30);
    expect(find.text('Sensor Dashboard'), findsOneWidget); // popped back

    h.gateway.emitTelemetry('greenhouse', {'temperature': 31});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('alert-banner')), findsOneWidget);
    expect(h.notifications.shown.single.limit, 30); // system notification requested
  });

  testWidgets('viewer: thresholds are read-only and never sent to the server', (tester) async {
    final h = await openSettings(tester, role: UserRole.viewer);

    expect(find.text('Only an admin can change alert thresholds.'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('threshold-temperature-max')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.enabled, isFalse);

    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();
    expect(h.api.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets('no developer hints on the settings screen', (tester) async {
    await openSettings(tester);
    expect(find.textContaining('adb'), findsNothing);
    expect(find.textContaining('npm'), findsNothing);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Live data address'), findsOneWidget);
  });

  testWidgets('invalid input shows field errors and does not save', (tester) async {
    final h = await openSettings(tester);

    await tester.enterText(find.byKey(const Key('settings-port')), '99999');
    await tester.enterText(find.byKey(const Key('settings-prefix')), 'sensors/#');
    await tester.enterText(find.byKey(const Key('settings-api-url')), 'not a url');
    await tester.enterText(find.byKey(const Key('threshold-humidity-min')), '90');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(find.text('Port must be a number from 1 to 65535'), findsOneWidget);
    expect(find.text('Wildcards (+, #) are not allowed'), findsOneWidget);
    expect(find.text('Enter an address like http://127.0.0.1:3000'), findsOneWidget);
    expect(find.text('Must be above min'), findsOneWidget);
    expect(h.repo.stored.port, 1883);
    expect(h.gateway.connectCalls, 1);
  });

  testWidgets('changing the sensor group reconnects and resubscribes', (tester) async {
    final h = await openSettings(tester);

    await tester.enterText(find.byKey(const Key('settings-prefix')), 'lab');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(h.gateway.connectCalls, 2);
    expect(h.gateway.subscriptions, containsAll(['lab/+/telemetry', 'lab/+/status']));
  });
}
