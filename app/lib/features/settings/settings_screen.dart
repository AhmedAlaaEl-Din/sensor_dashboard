import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../alerts/models/alert_models.dart';
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
  late final Map<SensorType, (TextEditingController, TextEditingController)> _limits;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _fill(context.read<SettingsController>().settings);
  }

  void _fill(AppSettings s, {bool reuse = false}) {
    String fmt(double? v) => v == null ? '' : _trim(v);
    if (!reuse) {
      _host = TextEditingController();
      _port = TextEditingController();
      _prefix = TextEditingController();
      _limits = {
        for (final sensor in SensorType.values)
          sensor: (TextEditingController(), TextEditingController()),
      };
    }
    _host.text = s.host;
    _port.text = '${s.port}';
    _prefix.text = s.topicPrefix;
    for (final sensor in SensorType.values) {
      final th = s.thresholds[sensor] ?? const SensorThreshold();
      _limits[sensor]!.$1.text = fmt(th.min);
      _limits[sensor]!.$2.text = fmt(th.max);
    }
    _themeMode = s.themeMode;
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _prefix.dispose();
    for (final (a, b) in _limits.values) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = context.read<SettingsController>();
    double? parse(TextEditingController c) =>
        c.text.trim().isEmpty ? null : double.parse(c.text.trim());

    final next = controller.settings.copyWith(
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      topicPrefix: _prefix.text.trim(),
      themeMode: _themeMode,
      thresholds: {
        for (final s in SensorType.values)
          s: SensorThreshold(min: parse(_limits[s]!.$1), max: parse(_limits[s]!.$2)),
      },
    );
    final error = await controller.save(next);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(error ?? 'Settings saved')));
    if (error == null) Navigator.of(context).maybePop();
  }

  void _resetDefaults() {
    setState(() => _fill(const AppSettings(), reuse: true));
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.select<SettingsController, bool>((c) => c.isSaving);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(onPressed: saving ? null : _resetDefaults, child: const Text('Defaults')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text('Broker', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Local broker only. With a USB phone, keep 127.0.0.1 and run '
              '"adb reverse tcp:1883 tcp:1883" on the computer.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('settings-host'),
              controller: _host,
              decoration: const InputDecoration(labelText: 'Host'),
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
                      labelText: 'Topic prefix',
                      helperText: 'Subscribes to <prefix>/+/telemetry',
                    ),
                    autocorrect: false,
                    validator: SettingsValidator.prefix,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Alert thresholds', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Leave a field empty for no limit.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final s in SensorType.values) ...[
              _ThresholdRow(
                sensor: s,
                min: _limits[s]!.$1,
                max: _limits[s]!.$2,
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            Text('Appearance', style: text.titleMedium),
            const SizedBox(height: 12),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto_outlined)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_outlined)),
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
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    );
  }
}

class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({required this.sensor, required this.min, required this.max});
  final SensorType sensor;
  final TextEditingController min;
  final TextEditingController max;

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
