import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/state_views.dart';
import '../alerts/alerts_controller.dart';
import '../alerts/alerts_screen.dart';
import '../alerts/widgets/alert_banner.dart';
import '../connection/connection_controller.dart';
import '../connection/widgets/connection_status_bar.dart';
import '../device_detail/device_detail_screen.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_screen.dart';
import '../telemetry/device_store.dart';
import '../telemetry/telemetry_parser.dart';
import 'widgets/device_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final activeCount = context.select<AlertsController, int>((a) => a.activeAlerts.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Dashboard'),
        actions: [
          IconButton(
            key: const Key('open-alerts'),
            tooltip: 'Alerts',
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const AlertsScreen())),
          ),
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => openSettings(context),
          ),
        ],
      ),
      body: const Column(
        children: [
          ConnectionStatusBar(),
          AlertBanner(),
          Expanded(child: _DashboardBody()),
        ],
      ),
    );
  }

  static void openSettings(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final connection = context.watch<ConnectionController>();
    final thresholds = context.watch<AlertsController>().thresholds;
    final prefix = TelemetryParser.normalizePrefix(
      context.select<SettingsController, String>((s) => s.settings.topicPrefix),
    );

    if (store.isEmpty) {
      switch (connection.status) {
        case ConnectionStatus.idle:
        case ConnectionStatus.connecting:
        case ConnectionStatus.reconnecting:
          return LoadingView(message: 'Connecting to the broker at ${connection.brokerLabel}…');
        case ConnectionStatus.offline:
          return MessageView(
            key: const Key('dashboard-error'),
            icon: Icons.cloud_off_outlined,
            isError: true,
            title: "Can't connect to the broker",
            body:
                connection.errorMessage ??
                'The broker at ${connection.brokerLabel} is not reachable.',
            actions: [
              FilledButton.icon(
                onPressed: connection.retryNow,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry now'),
              ),
              OutlinedButton.icon(
                onPressed: () => DashboardScreen.openSettings(context),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Check settings'),
              ),
            ],
          );
        case ConnectionStatus.connected:
          return MessageView(
            key: const Key('dashboard-empty'),
            icon: Icons.sensors_outlined,
            title: 'Connected. Waiting for sensor data',
            body:
                'Listening on "$prefix/+/telemetry". Start the simulator with '
                '"npm run simulate" in the broker folder.',
          );
      }
    }

    final devices = store.devices;
    return RefreshIndicator(
      onRefresh: connection.retryNow,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final d = devices[i];
          return DeviceCard(
            device: d,
            thresholds: thresholds,
            live: connection.isConnected,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => DeviceDetailScreen(deviceId: d.id))),
          );
        },
      ),
    );
  }
}
