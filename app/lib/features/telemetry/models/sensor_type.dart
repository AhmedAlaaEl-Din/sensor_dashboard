/// The four sensors every simulated device reports.
enum SensorType {
  temperature(
    key: 'temperature',
    label: 'Temperature',
    unit: '°C',
    gaugeMin: -10,
    gaugeMax: 50,
    decimals: 1,
    hysteresis: 0.5,
  ),
  humidity(
    key: 'humidity',
    label: 'Humidity',
    unit: '%',
    gaugeMin: 0,
    gaugeMax: 100,
    decimals: 1,
    hysteresis: 1,
  ),
  pressure(
    key: 'pressure',
    label: 'Pressure',
    unit: 'hPa',
    gaugeMin: 950,
    gaugeMax: 1050,
    decimals: 1,
    hysteresis: 1,
  ),
  battery(
    key: 'battery',
    label: 'Battery',
    unit: '%',
    gaugeMin: 0,
    gaugeMax: 100,
    decimals: 0,
    hysteresis: 1,
  );

  const SensorType({
    required this.key,
    required this.label,
    required this.unit,
    required this.gaugeMin,
    required this.gaugeMax,
    required this.decimals,
    required this.hysteresis,
  });

  /// JSON field name in the telemetry payload.
  final String key;
  final String label;
  final String unit;

  /// Range used to draw the gauge (values outside are clamped visually).
  final double gaugeMin;
  final double gaugeMax;
  final int decimals;

  /// How far a value must move back inside a threshold before an alert clears.
  /// Prevents alerts from flapping when a value hovers on the limit.
  final double hysteresis;

  String format(double value) => '${value.toStringAsFixed(decimals)} $unit';

  static SensorType? fromKey(String key) {
    for (final s in SensorType.values) {
      if (s.key == key) return s;
    }
    return null;
  }
}
