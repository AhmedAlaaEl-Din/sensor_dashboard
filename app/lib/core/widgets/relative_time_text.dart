import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// "just now", "12 s ago", "3 min ago". Updates itself every second.
String relativeTime(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inSeconds < 2) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds} s ago';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class RelativeTimeText extends StatefulWidget {
  const RelativeTimeText(this.time, {super.key, this.prefix = '', this.style});

  final DateTime? time;
  final String prefix;
  final TextStyle? style;

  @override
  State<RelativeTimeText> createState() => _RelativeTimeTextState();
}

class _RelativeTimeTextState extends State<RelativeTimeText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.time;
    return Text(
      t == null ? '${widget.prefix}never' : '${widget.prefix}${relativeTime(t, DateTime.now())}',
      style: widget.style,
    );
  }
}
