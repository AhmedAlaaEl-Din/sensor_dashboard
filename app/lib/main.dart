import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'core/mqtt/mqtt_gateway.dart';
import 'features/alerts/notification_service.dart';
import 'features/auth/token_store.dart';
import 'features/settings/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = SharedPrefsSettingsRepository();
  final initial = await repository.load(); // Never throws; falls back to defaults.

  final services = AppServices(
    gateway: MqttClientGateway(),
    repository: repository,
    tokenStore: SecureTokenStore(),
    notifications: LocalNotificationService(),
    initialSettings: initial,
  );

  runApp(SensorDashboardApp(services: services));
  await services.start();
}
