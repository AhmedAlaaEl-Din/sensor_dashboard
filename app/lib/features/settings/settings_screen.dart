import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../alerts/models/alert_models.dart';
import '../auth/auth_controller.dart';
import '../telemetry/models/sensor_type.dart';
import 'models/app_settings.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _prefix;
  late final TextEditingController _apiUrl;
  late final Map<SensorType, (TextEditingController, TextEditingController)> _limits;
  late ThemeMode _themeMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fill(context.read<SettingsController>().settings);
  }

  void _fill(AppSettings s, {bool reuse = false, bool includeThresholds = true}) {
    String fmt(double? v) => v == null ? '' : _trim(v);
    if (!reuse) {
      _host = TextEditingController();
      _port = TextEditingController();
      _prefix = TextEditingController();
      _apiUrl = TextEditingController();
      _limits = {
        for (final sensor in SensorType.values)
          sensor: (TextEditingController(), TextEditingController()),
      };
    }
    _host.text = s.host;
    _port.text = '${s.port}';
    _prefix.text = s.topicPrefix;
    _apiUrl.text = s.apiUrl;
    if (includeThresholds) {
      for (final sensor in SensorType.values) {
        final th = s.thresholds[sensor] ?? const SensorThreshold();
        _limits[sensor]!.$1.text = fmt(th.min);
        _limits[sensor]!.$2.text = fmt(th.max);
      }
    }
    _themeMode = s.themeMode;
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    for (final c in [_host, _port, _prefix, _apiUrl]) {
      c.dispose();
    }
    for (final (a, b) in _limits.values) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Map<SensorType, SensorThreshold> _thresholdsFromFields() {
    double? parse(TextEditingController c) =>
        c.text.trim().isEmpty ? null : double.parse(c.text.trim());
    return {
      for (final s in SensorType.values)
        s: SensorThreshold(min: parse(_limits[s]!.$1), max: parse(_limits[s]!.$2)),
    };
  }

  bool _sameThresholds(Map<SensorType, SensorThreshold> a, Map<SensorType, SensorThreshold> b) =>
      SensorType.values.every(
        (s) => (a[s] ?? const SensorThreshold()) == (b[s] ?? const SensorThreshold()),
      );

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = context.read<SettingsController>();
    final auth = context.read<AuthController>();
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(m)));
    }

    setState(() => _saving = true);
    try {
      var thresholds = controller.settings.thresholds;
      final edited = _thresholdsFromFields();
      if (auth.isAdmin && !_sameThresholds(edited, thresholds)) {
        // Thresholds are shared: the server stores them and checks the role.
        try {
          thresholds = await api.putThresholds(edited);
        } on ApiException catch (e) {
          if (mounted) say(e.message);
          return;
        }
      }

      final next = controller.settings.copyWith(
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        topicPrefix: _prefix.text.trim(),
        apiUrl: _apiUrl.text.trim(),
        themeMode: _themeMode,
        thresholds: thresholds,
      );
      final error = await controller.save(next);
      if (!mounted) return;
      say(error ?? 'Settings saved');
      if (error == null) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetDefaults(bool canEditThresholds) {
    setState(() => _fill(const AppSettings(), reuse: true, includeThresholds: canEditThresholds));
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving || context.select<SettingsController, bool>((c) => c.isSaving);
    final auth = context.watch<AuthController>();
    final signedIn = auth.isSignedIn;
    final canEdit = auth.isAdmin;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final note = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: saving ? null : () => _resetDefaults(canEdit),
            child: const Text('Defaults'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (signedIn) ...[
              Text('Alert thresholds', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                canEdit
                    ? 'Shared with everyone. Leave a field empty for no limit.'
                    : 'Only an admin can change alert thresholds.',
                key: const Key('thresholds-note'),
                style: note,
              ),
              const SizedBox(height: 12),
              for (final s in SensorType.values) ...[
                _ThresholdRow(
                  sensor: s,
                  min: _limits[s]!.$1,
                  max: _limits[s]!.$2,
                  enabled: canEdit,
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 16),
            ],
            Text('Connection', style: text.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('settings-api-url'),
              controller: _apiUrl,
              decoration: const InputDecoration(
                labelText: 'Server address',
                helperText: 'Used for sign-in, history and export',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: SettingsValidator.apiUrl,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('settings-host'),
              controller: _host,
              decoration: const InputDecoration(labelText: 'Live data address'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: SettingsValidator.host,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    key: const Key('settings-port'),
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    validator: SettingsValidator.port,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('settings-prefix'),
                    controller: _prefix,
                    decoration: const InputDecoration(
                      labelText: 'Sensor group',
                      helperText: 'Usually "sensors"',
                    ),
                    autocorrect: false,
                    validator: SettingsValidator.prefix,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Appearance', style: text.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {_themeMode},
              onSelectionChanged: (v) => setState(() => _themeMode = v.first),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('settings-save'),
        onPressed: saving ? null : _save,
        icon: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.sensor,
    required this.min,
    required this.max,
    required this.enabled,
  });
  final SensorType sensor;
  final TextEditingController min;
  final TextEditingController max;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 104,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(sensor.label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
        Expanded(
          child: TextFormField(
            key: Key('threshold-${sensor.key}-min'),
            controller: min,
            enabled: enabled,
            decoration: InputDecoration(labelText: 'Min', suffixText: sensor.unit),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            validator: SettingsValidator.number,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: Key('threshold-${sensor.key}-max'),
            controller: max,
            enabled: enabled,
            decoration: InputDecoration(labelText: 'Max', suffixText: sensor.unit),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            validator: (v) {
              final basic = SettingsValidator.number(v);
              if (basic != null) return basic;
              final lo = double.tryParse(min.text.trim());
              final hi = double.tryParse(v?.trim() ?? '');
              if (lo != null && hi != null && hi <= lo) return 'Must be above min';
              return null;
            },
          ),
        ),
      ],
    );
  }
}
