import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensor_dashboard/app/app.dart';
import 'package:sensor_dashboard/app/app_services.dart';
import 'package:sensor_dashboard/features/settings/settings_repository.dart';

import '../helpers/fake_gateway.dart';

/// Builds the real app around a fake MQTT gateway.
Future<(AppServices, FakeGateway)> pumpApp(WidgetTester tester, {FakeGateway? gateway}) async {
  final gw = gateway ?? FakeGateway();
  final services = AppServices(
    gateway: gw,
    repository: InMemorySettingsRepository(),
    backoff: (_) => const Duration(seconds: 30),
  );
  addTearDown(services.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(SensorDashboardApp(services: services));
  unawaited(services.start());
  await tester.pump();
  return (services, gw);
}

Map<String, Object?> normal({double temperature = 24.3}) => {
  'temperature': temperature,
  'humidity': 55.2,
  'pressure': 1013.4,
  'battery': 88,
  'timestamp': DateTime.now().toUtc().toIso8601String(),
};

void main() {
  testWidgets('shows a loading state while connecting', (tester) async {
    final gw = FakeGateway()..pendingConnect = Completer<void>();
    await pumpApp(tester, gateway: gw);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.textContaining('Connecting to the broker at 127.0.0.1:1883'), findsOneWidget);

    gw.pendingConnect!.complete();
    await tester.pump();
  });

  testWidgets('shows an empty state when connected but no data yet', (tester) async {
    await pumpApp(tester);
    await tester.pump();

    expect(find.byKey(const Key('dashboard-empty')), findsOneWidget);
    expect(find.textContaining('sensors/+/telemetry'), findsOneWidget);
    expect(find.textContaining('Live · connected to 127.0.0.1:1883'), findsOneWidget);
  });

  testWidgets('shows a friendly error state when the broker is unreachable', (tester) async {
    final gw = FakeGateway()..failConnect = true;
    await pumpApp(tester, gateway: gw);
    await tester.pump();

    expect(find.byKey(const Key('dashboard-error')), findsOneWidget);
    expect(find.text("Can't connect to the broker"), findsOneWidget);
    expect(find.textContaining('adb reverse'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
    // No raw exception text anywhere.
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.textContaining('OS Error'), findsNothing);

    // Retry now recovers once the broker is up.
    gw.failConnect = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Retry now'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('dashboard-empty')), findsOneWidget);
  });

  testWidgets('renders a card per device with live gauge values', (tester) async {
    final (_, gw) = await pumpApp(tester);
    await tester.pump();

    gw.emitTelemetry('greenhouse', normal());
    gw.emitTelemetry('warehouse', normal(temperature: 18));
    gw.emit('sensors/server-room/status', 'offline');
    await tester.pump();

    expect(find.byKey(const Key('device-card-greenhouse')), findsOneWidget);
    expect(find.byKey(const Key('device-card-warehouse')), findsOneWidget);
    expect(find.text('Greenhouse'), findsOneWidget);
    expect(find.text('Server Room'), findsOneWidget);
    expect(find.text('Device is offline. No readings yet.'), findsOneWidget);
    expect(find.text('24.3'), findsOneWidget);
    expect(find.text('1013.4'), findsNWidgets(2));
    expect(find.text('Online'), findsNWidgets(2));
    expect(find.text('Offline'), findsOneWidget);

    // Values update live.
    gw.emitTelemetry('greenhouse', normal(temperature: 26.1));
    await tester.pump();
    expect(find.text('26.1'), findsOneWidget);
    expect(find.text('24.3'), findsNothing);
  });

  testWidgets('a spike shows the alert banner and badge; dismiss hides it', (tester) async {
    final (services, gw) = await pumpApp(tester);
    await tester.pump();

    gw.emitTelemetry('greenhouse', normal());
    await tester.pump();
    expect(find.byKey(const Key('alert-banner')), findsNothing);

    gw.emitTelemetry('greenhouse', normal(temperature: 43.8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('alert-banner')), findsOneWidget);
    expect(find.textContaining('Greenhouse: Temperature 43.8 °C is above 35.0 °C'), findsOneWidget);
    expect(services.alerts.activeAlerts, hasLength(1));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('alert-banner')), findsNothing);
    // Still active in history (badge stays).
    expect(services.alerts.activeAlerts, hasLength(1));
  });

  testWidgets('losing the connection shows offline and keeps the last values', (tester) async {
    final (_, gw) = await pumpApp(tester);
    await tester.pump();
    gw.emitTelemetry('greenhouse', normal());
    await tester.pump();

    gw.failConnect = true;
    gw.dropConnection();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('No connection'), findsOneWidget);
    expect(find.text('24.3'), findsOneWidget); // stale value still visible
  });

  testWidgets('tapping a card opens the detail screen with stats', (tester) async {
    final (_, gw) = await pumpApp(tester);
    await tester.pump();
    for (final t in [20.0, 22.0, 24.0]) {
      gw.emitTelemetry('warehouse', normal(temperature: t));
    }
    await tester.pump();

    await tester.tap(find.byKey(const Key('device-card-warehouse')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    expect(find.text('Warehouse'), findsOneWidget); // app bar title
    expect(find.byKey(const Key('stat-min')), findsOneWidget);
    expect(find.text('20.0 °C'), findsOneWidget);
    expect(find.text('22.0 °C'), findsOneWidget);
    expect(find.text('24.0 °C'), findsWidgets);
  });

  testWidgets('dark theme renders the dashboard', (tester) async {
    final (services, gw) = await pumpApp(tester);
    await services.settings.save(services.settings.settings.copyWith(themeMode: ThemeMode.dark));
    await tester.pump();
    gw.emitTelemetry('greenhouse', normal());
    await tester.pump(const Duration(milliseconds: 500)); // theme cross-fade
    final ctx = tester.element(find.byKey(const Key('device-card-greenhouse')));
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });
}
