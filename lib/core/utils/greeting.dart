/// Time-of-day greeting shown on the dashboard.
///
/// Buckets: morning 5:00–11:59, afternoon 12:00–16:59, evening 17:00–20:59,
/// night 21:00–4:59. Kept out of the widget so the boundaries can be tested.
String greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}

/// The name to greet.
///
/// Prefers the display name as-is — never truncated to a single word, so
/// "A R Prathap" is greeted in full rather than as "A". Falls back to the
/// local part of an email address, then to a neutral "there".
String greetingName(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return 'there';
  if (name.contains('@')) {
    final local = name.split('@').first.trim();
    return local.isEmpty ? 'there' : local;
  }
  return name;
}

/// The name to show for the signed-in user, most specific source first.
///
/// This matters most offline. The Firestore profile document may not have
/// resolved yet — or may never have been cached, on a first run with no
/// network — while Firebase Auth keeps the display name and address on disk
/// across restarts. Falling through in this order means a cold start with no
/// network still shows a name instead of a placeholder, and that the avatar
/// beside it has initials to draw.
///
/// [fallback] is the last resort for an account with no name and no address.
String resolveDisplayName({
  String? profileName,
  String? authName,
  String? email,
  required String fallback,
}) {
  for (final candidate in [profileName, authName, email]) {
    final value = candidate?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}
