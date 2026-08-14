const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Renders a UTC-stored timestamp as a short relative label, e.g. "3h ago".
/// Falls back to the absolute date once it's a week old or more, so labels
/// never grow unboundedly long.
String formatRelativeTime(DateTime storedUtc, {DateTime? now}) {
  final local = storedUtc.toLocal();
  final reference = now ?? DateTime.now();
  final diff = reference.difference(local);

  if (diff.inSeconds < 5) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatAbsoluteDate(storedUtc);
}

/// Renders a UTC-stored timestamp as an absolute local date/time.
String formatAbsoluteDate(DateTime storedUtc) {
  final local = storedUtc.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${_months[local.month - 1]} ${local.day}, ${local.year}, $hour12:$minute $period';
}
