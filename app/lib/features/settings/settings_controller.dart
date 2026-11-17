import 'package:flutter/foundation.dart';

import 'models/app_settings.dart';
import 'settings_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._repository, [AppSettings initial = const AppSettings()])
      : _settings = initial;

  final SettingsRepository _repository;
  AppSettings _settings;
  bool _saving = false;

  AppSettings get settings => _settings;
  bool get isSaving => _saving;

  Future<void> load() async {
    _settings = await _repository.load();
    notifyListeners();
  }

  /// Returns null on success, or a friendly error message.
  Future<String?> save(AppSettings next) async {
    _saving = true;
    _settings = next; // Apply right away so the app reacts even if storage fails.
    notifyListeners();
    try {
      await _repository.save(next);
      return null;
    } catch (e) {
      debugPrint('Settings save failed: $e');
      return 'Settings are applied but could not be saved on this device.';
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
