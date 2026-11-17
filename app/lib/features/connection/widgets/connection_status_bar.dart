import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../connection_controller.dart';

/// Thin bar under the app bar: always tells the user whether data is live.
class ConnectionStatusBar extends StatefulWidget {
  const ConnectionStatusBar({super.key});

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar> {
  Timer? _tick; // Refreshes the "retrying in N s" countdown.

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<ConnectionController>().status == ConnectionStatus.offline) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectionController>();
    final scheme = Theme.of(context).colorScheme;

    final (Color bg, Color fg, Widget leading, String label) = switch (c.status) {
      ConnectionStatus.connected => (
        scheme.ok.withValues(alpha: 0.14),
        scheme.ok,
        Icon(Icons.cloud_done_outlined, size: 18, color: scheme.ok),
        'Live · connected to ${c.brokerLabel}',
      ),
      ConnectionStatus.idle || ConnectionStatus.connecting => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        _spinner(scheme.onSecondaryContainer),
        'Connecting to ${c.brokerLabel}…',
      ),
      ConnectionStatus.reconnecting => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        _spinner(scheme.onSecondaryContainer),
        'Reconnecting to ${c.brokerLabel}…',
      ),
      ConnectionStatus.offline => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onErrorContainer),
        'Offline · ${_retryLabel(c.nextRetryAt)}',
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        key: const Key('connection-status-bar'),
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.status == ConnectionStatus.offline)
                TextButton(
                  onPressed: c.retryNow,
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Retry now'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _spinner(Color color) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );

  static String _retryLabel(DateTime? at) {
    if (at == null) return 'retrying soon';
    final s = at.difference(DateTime.now()).inSeconds;
    return s <= 0 ? 'retrying…' : 'retrying in $s s';
  }
}
