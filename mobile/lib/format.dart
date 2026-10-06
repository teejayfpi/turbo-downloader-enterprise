String formatBytes(int bytes, {int digits = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : digits)} ${units[unit]}';
}

String formatSpeed(int bytesPerSecond) =>
    bytesPerSecond <= 0 ? '—' : '${formatBytes(bytesPerSecond)}/s';

String formatDuration(int? seconds) {
  if (seconds == null || seconds <= 0) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String formatRelative(DateTime? time) {
  if (time == null) return '—';
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

/// A friendly label for a scheduled start time: a relative countdown for the
/// next few hours, otherwise a weekday and clock time.
String formatStartAt(DateTime? time) {
  if (time == null) return 'Now';
  final now = DateTime.now();
  final diff = time.difference(now);
  if (diff.isNegative) return 'Now';
  if (diff.inMinutes < 1) return 'in under a minute';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
  if (diff.inHours < 6) {
    final m = diff.inMinutes % 60;
    return m == 0 ? 'in ${diff.inHours} h' : 'in ${diff.inHours} h $m min';
  }
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final sameDay = time.year == now.year &&
      time.month == now.month &&
      time.day == now.day;
  final tomorrow = time.year == now.year &&
      time.month == now.month &&
      time.day == now.day + 1;
  final clock = _clock(time);
  if (sameDay) return 'today at $clock';
  if (tomorrow) return 'tomorrow at $clock';
  return '${days[time.weekday - 1]} ${time.day}/${time.month} at $clock';
}

String _clock(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
