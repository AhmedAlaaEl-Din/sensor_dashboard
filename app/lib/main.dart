import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'core/mqtt/mqtt_gateway.dart';
import 'features/settings/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = SharedPrefsSettingsRepository();
  final initial = await repository.load(); // Never throws; falls back to defaults.

  final services = AppServices(
    gateway: MqttClientGateway(),
    repository: repository,
    initialSettings: initial,
  );

  runApp(SensorDashboardApp(services: services));
  services.start();
}
