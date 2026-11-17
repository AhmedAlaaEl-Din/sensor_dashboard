import 'dart:collection';

/// Minimum, maximum and average of a series of values.
class SensorStats {
  const SensorStats({
    required this.min,
    required this.max,
    required this.average,
    required this.count,
  });

  final double min;
  final double max;
  final double average;
  final int count;

  /// Returns null when there are no finite values.
  static SensorStats? fromValues(Iterable<double> values) {
    var count = 0;
    var sum = 0.0;
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final v in values) {
      if (!v.isFinite) continue;
      count++;
      sum += v;
      if (v < min) min = v;
      if (v > max) max = v;
    }
    if (count == 0) return null;
    return SensorStats(min: min, max: max, average: sum / count, count: count);
  }
}

/// Fixed-size buffer that drops the oldest item when full.
class RollingBuffer<T> extends IterableBase<T> {
  RollingBuffer(this.capacity) : assert(capacity > 0);

  final int capacity;
  final ListQueue<T> _items = ListQueue<T>();

  void add(T item) {
    _items.addLast(item);
    while (_items.length > capacity) {
      _items.removeFirst();
    }
  }

  void clear() => _items.clear();

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  int get length => _items.length;
}
