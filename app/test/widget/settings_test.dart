import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensor_dashboard/app/app.dart';
import 'package:sensor_dashboard/app/app_services.dart';
import 'package:sensor_dashboard/features/settings/settings_repository.dart';
import 'package:sensor_dashboard/features/telemetry/models/sensor_type.dart';

import '../helpers/fake_gateway.dart';

void main() {
  Future<(AppServices, FakeGateway, InMemorySettingsRepository)> pump(WidgetTester tester) async {
    final gw = FakeGateway();
    final repo = InMemorySettingsRepository();
    final services = AppServices(gateway: gw, repository: repo);
    addTearDown(services.dispose);
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(SensorDashboardApp(services: services));
    await services.start();
    await tester.pump();
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();
    return (services, gw, repo);
  }

  testWidgets('changing a threshold saves it and applies it to alerts', (tester) async {
    final (services, gw, repo) = await pump(tester);

    await tester.enterText(find.byKey(const Key('threshold-temperature-max')), '30');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(repo.stored.thresholds[SensorType.temperature]!.max, 30);
    expect(services.alerts.thresholds[SensorType.temperature]!.max, 30);
    expect(find.text('Sensor Dashboard'), findsOneWidget); // popped back

    gw.emitTelemetry('greenhouse', {'temperature': 31});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('alert-banner')), findsOneWidget);
  });

  testWidgets('invalid input shows field errors and does not save', (tester) async {
    final (_, gw, repo) = await pump(tester);

    await tester.enterText(find.byKey(const Key('settings-port')), '99999');
    await tester.enterText(find.byKey(const Key('settings-prefix')), 'sensors/#');
    await tester.enterText(find.byKey(const Key('threshold-humidity-min')), '90');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(find.text('Port must be a number from 1 to 65535'), findsOneWidget);
    expect(find.text('Wildcards (+, #) are not allowed'), findsOneWidget);
    expect(find.text('Must be above min'), findsOneWidget);
    expect(repo.stored.port, 1883);
    expect(gw.connectCalls, 1);
  });

  testWidgets('changing the prefix reconnects and resubscribes', (tester) async {
    final (_, gw, _) = await pump(tester);

    await tester.enterText(find.byKey(const Key('settings-prefix')), 'lab');
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(gw.connectCalls, 2);
    expect(gw.subscriptions, containsAll(['lab/+/telemetry', 'lab/+/status']));
  });
}
