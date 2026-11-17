import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/settings/settings_controller.dart';
import 'app_services.dart';

class SensorDashboardApp extends StatelessWidget {
  const SensorDashboardApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: services.settings),
        ChangeNotifierProvider.value(value: services.devices),
        ChangeNotifierProvider.value(value: services.alerts),
        ChangeNotifierProvider.value(value: services.connection),
      ],
      child: Builder(
        builder: (context) {
          final themeMode = context.select<SettingsController, ThemeMode>(
            (s) => s.settings.themeMode,
          );
          return MaterialApp(
            title: 'Sensor Dashboard',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: const DashboardScreen(),
          );
        },
      ),
    );
  }
}
