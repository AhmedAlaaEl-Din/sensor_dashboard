import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/api/api_client.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/state_views.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/history/csv_exporter.dart';
import '../features/settings/settings_controller.dart';
import 'app_services.dart';

class SensorDashboardApp extends StatefulWidget {
  const SensorDashboardApp({super.key, required this.services});

  final AppServices services;

  @override
  State<SensorDashboardApp> createState() => _SensorDashboardAppState();
}

class _SensorDashboardAppState extends State<SensorDashboardApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Timers may not fire while backgrounded; re-check the session on resume.
    _lifecycle = AppLifecycleListener(onResume: widget.services.auth.checkExpiry);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: s.settings),
        ChangeNotifierProvider.value(value: s.devices),
        ChangeNotifierProvider.value(value: s.alerts),
        ChangeNotifierProvider.value(value: s.connection),
        ChangeNotifierProvider.value(value: s.auth),
        Provider<ApiClient>.value(value: s.api),
        Provider<CsvExporter>.value(value: s.exporter),
        Provider<FileSharer>.value(value: s.sharer),
      ],
      child: Builder(
        builder: (context) {
          final themeMode = context.select<SettingsController, ThemeMode>(
            (c) => c.settings.themeMode,
          );
          final status = context.select<AuthController, AuthStatus>((a) => a.status);
          return MaterialApp(
            title: 'Sensor Dashboard',
            debugShowCheckedModeBanner: false,
            navigatorKey: s.navigatorKey,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            home: switch (status) {
              AuthStatus.restoring => const Scaffold(body: LoadingView(message: 'Starting…')),
              AuthStatus.signedOut => const LoginScreen(),
              AuthStatus.signedIn => const DashboardScreen(),
            },
          );
        },
      ),
    );
  }
}
