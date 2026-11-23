import 'package:flutter/material.dart';

/// "Expires in 4:32" with a bar that empties as the 5 minutes run out.
/// Turns to the error colour for the last 30 seconds; no animation beyond
/// the once-a-second tick the parent drives.
class Countdown extends StatelessWidget {
  const Countdown({
    super.key,
    required this.createdAt,
    required this.expiresAt,
    required this.now,
  });

  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime now;

  static const urgent = Duration(seconds: 30);

  Duration get remaining {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  double get fraction {
    final total = expiresAt.difference(createdAt).inMilliseconds;
    if (total <= 0) return 0;
    return (remaining.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static String format(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUrgent = remaining <= urgent;
    final color = isUrgent ? scheme.error : scheme.onSurfaceVariant;
    final text = 'Expires in ${format(remaining)}';
    return Semantics(
      label: text,
      liveRegion: isUrgent,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              color: isUrgent ? scheme.error : scheme.primary,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
