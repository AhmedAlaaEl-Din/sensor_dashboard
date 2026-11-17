import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_settings.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// Stores settings on the device with shared_preferences.
class SharedPrefsSettingsRepository implements SettingsRepository {
  static const _kHost = 'broker.host';
  static const _kPort = 'broker.port';
  static const _kPrefix = 'broker.prefix';
  static const _kThresholds = 'alerts.thresholds';
  static const _kTheme = 'ui.themeMode';

  @override
  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = prefs.getString(_kHost);
      final port = prefs.getInt(_kPort);
      final prefix = prefs.getString(_kPrefix);
      final thresholdsJson = prefs.getString(_kThresholds);
      final themeIndex = prefs.getInt(_kTheme);

      return AppSettings(
        host: (host != null && SettingsValidator.host(host) == null)
            ? host
            : AppSettings.defaultHost,
        port: (port != null && SettingsValidator.port('$port') == null)
            ? port
            : AppSettings.defaultPort,
        topicPrefix: (prefix != null && SettingsValidator.prefix(prefix) == null)
            ? prefix
            : AppSettings.defaultPrefix,
        thresholds: thresholdsJson == null
            ? const AppSettings().thresholds
            : AppSettings.thresholdsFromJson(jsonDecode(thresholdsJson) as Map<String, dynamic>),
        themeMode: (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length)
            ? ThemeMode.values[themeIndex]
            : ThemeMode.system,
      );
    } catch (e, st) {
      // Corrupt or unreadable storage: fall back to defaults, never crash.
      debugPrint('Settings load failed, using defaults: $e\n$st');
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHost, s.host);
    await prefs.setInt(_kPort, s.port);
    await prefs.setString(_kPrefix, s.topicPrefix);
    await prefs.setString(_kThresholds, jsonEncode(s.thresholdsToJson()));
    await prefs.setInt(_kTheme, s.themeMode.index);
  }
}

/// For tests.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([this.stored = const AppSettings()]);
  AppSettings stored;

  @override
  Future<AppSettings> load() async => stored;

  @override
  Future<void> save(AppSettings settings) async => stored = settings;
}
