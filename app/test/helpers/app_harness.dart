import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sensor_dashboard/app/app.dart';
import 'package:sensor_dashboard/app/app_services.dart';
import 'package:sensor_dashboard/features/alerts/notification_service.dart';
import 'package:sensor_dashboard/features/auth/models/session.dart';
import 'package:sensor_dashboard/features/auth/token_store.dart';
import 'package:sensor_dashboard/features/history/csv_exporter.dart';
import 'package:sensor_dashboard/features/settings/settings_repository.dart';

import 'fake_api.dart';
import 'fake_gateway.dart';

class RecordingSharer implements FileSharer {
  final List<String> shared = [];
  @override
  Future<void> shareFile(String path, {required String subject}) async => shared.add(path);
}

class Harness {
  Harness(this.services, this.gateway, this.api, this.repo, this.notifications, this.sharer);
  final AppServices services;
  final FakeGateway gateway;
  final FakeApi api;
  final InMemorySettingsRepository repo;
  final NoopNotificationService notifications;
  final RecordingSharer sharer;
}

/// Builds the real app around a fake MQTT gateway and a fake API.
/// [role] null means "start signed out".
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeGateway? gateway,
  UserRole? role = UserRole.viewer,
  Size size = const Size(420, 900),
}) async {
  final gw = gateway ?? FakeGateway();
  final api = FakeApi();
  final repo = InMemorySettingsRepository();
  final notifications = NoopNotificationService();
  final sharer = RecordingSharer();
  final store = MemoryTokenStore(
    role == null
        ? null
        : FakeApi.session(role, expiresAt: DateTime.now().add(const Duration(hours: 1))),
  );
  final services = AppServices(
    gateway: gw,
    repository: repo,
    tokenStore: store,
    httpClient: api.client,
    notifications: notifications,
    sharer: sharer,
    exportDirectory: () async => Directory.systemTemp.createTemp('export_test'),
    backoff: (_) => const Duration(seconds: 30),
  );
  addTearDown(services.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(SensorDashboardApp(services: services));
  unawaited(services.start());
  await tester.pump();
  await tester.pump();
  return Harness(services, gw, api, repo, notifications, sharer);
}
