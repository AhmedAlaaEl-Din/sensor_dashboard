import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../telemetry/models/telemetry.dart';
import 'models/alert_models.dart';

/// Shows a system notification when an alert triggers.
abstract interface class NotificationService {
  /// [onOpenDevice] is called with a device id when the user taps a notification.
  Future<void> init({required void Function(String deviceId) onOpenDevice});

  /// Asks for permission where Android requires it (Android 13+).
  Future<void> requestPermission();

  Future<void> showAlert(AlertEvent alert);
}

/// Used in tests and anywhere notifications are not wanted.
class NoopNotificationService implements NotificationService {
  final List<AlertEvent> shown = [];

  @override
  Future<void> init({required void Function(String deviceId) onOpenDevice}) async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> showAlert(AlertEvent alert) async => shown.add(alert);
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const channelId = 'sensor_alerts';
  static const _channel = AndroidNotificationChannel(
    channelId,
    'Sensor alerts',
    description: 'A reading went outside its threshold.',
    importance: Importance.high, // heads-up banner + sound
  );

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<void> init({required void Function(String deviceId) onOpenDevice}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) onOpenDevice(id);
        },
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);

      // App was started by tapping a notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if ((launch?.didNotificationLaunchApp ?? false) && payload != null && payload.isNotEmpty) {
        onOpenDevice(payload);
      }
      _ready = true;
    } catch (e) {
      // Notifications are a bonus; the in-app banner still works.
      debugPrint('Notifications unavailable: ${e.runtimeType}');
    }
  }

  @override
  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission request failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> showAlert(AlertEvent alert) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: alert.id & 0x7fffffff,
        title: '${displayNameFor(alert.deviceId)}: ${alert.sensor.label.toLowerCase()} alert',
        body: alert.description,
        payload: alert.deviceId,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.status,
            ticker: 'Sensor alert',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not show notification: ${e.runtimeType}');
    }
  }
}
