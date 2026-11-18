/// The owner's period, written into the engine's own groups.
///
/// mihomo times a `url-test`, `fallback` or `load-balance` group every `interval` seconds and
/// keeps the result in the proxy's own history — the numbers the app reads back. A subscription
/// that ships `interval: 0` (or none at all) therefore hands the owner a list that never
/// refreshes on its own, which is the case the switch exists for.
///
/// The rule is narrow on purpose:
///   * only groups that time themselves are touched — a `select` group has no such field;
///   * a provider's own number is kept, whatever it is, as long as it is above zero;
///   * zero is never written: "off" is the switch, not a number, and a group told to check every
///     zero seconds means "never".
///
/// The map handed in is the document that goes to the core, never the file on disk, so a
/// subscription update cannot lose the value and the provider's file stays the provider's.
library;

/// The groups whose members are timed by the engine.
const _timedGroupTypes = {'url-test', 'fallback', 'load-balance'};

/// How many groups [applyAutoPingInterval] changed.
int applyAutoPingInterval(Map<String, dynamic> rawConfig, int? seconds) {
  // Null is "no opinion": the switch is off, or the owner chose the provider's own value.
  if (seconds == null || seconds <= 0) return 0;
  final groups = rawConfig['proxy-groups'];
  if (groups is! List) return 0;
  var written = 0;
  for (final group in groups) {
    if (group is! Map) continue;
    final type = '${group['type'] ?? ''}'.toLowerCase();
    if (!_timedGroupTypes.contains(type)) continue;
    final existing = group['interval'];
    final value = existing is int ? existing : int.tryParse('${existing ?? ''}');
    if (value != null && value > 0) continue;
    group['interval'] = seconds;
    written++;
  }
  return written;
}
