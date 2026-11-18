part of '../state.dart';

/// The interval the subscription itself gives its timed groups, in seconds.
///
/// The network mode's dialog offers "as in the subscription" next to the owner's own periods, and
/// that row has to say which number it means — otherwise the owner chooses a word and cannot see
/// what it does. This reads the profile's YAML the way the engine will: `url-test`, `fallback` and
/// `load-balance` groups only, since a `select` group has no clock at all.
///
/// Null means the subscription names no such interval (missing or zero in every timed group): the
/// engine then never re-times a group on its own, which is exactly the case the switch exists for.
final subscriptionPingIntervalProvider =
    FutureProvider.autoDispose<Duration?>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return null;
  try {
    final file = await profile.file;
    if (!await file.exists()) return null;
    final document = loadYaml(await file.readAsString());
    if (document is! Map) return null;
    final groups = document['proxy-groups'];
    if (groups is! List) return null;
    const timed = {'url-test', 'fallback', 'load-balance'};
    final values = <int>[];
    for (final group in groups) {
      if (group is! Map) continue;
      if (!timed.contains('${group['type'] ?? ''}'.toLowerCase())) continue;
      final raw = group['interval'];
      final value = raw is int ? raw : int.tryParse('${raw ?? ''}');
      if (value != null && value > 0) values.add(value);
    }
    if (values.isEmpty) return null;
    // The groups usually share one number; when they do not, the shortest is the honest answer:
    // it is the one that will be checked most often and so the one the owner will notice.
    values.sort();
    return Duration(seconds: values.first);
  } catch (_) {
    return null;
  }
});
