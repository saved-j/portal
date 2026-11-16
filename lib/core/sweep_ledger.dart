/// The bookkeeping a delay sweep needs, without a widget, a provider or a socket.
///
/// Two facts decide everything a sweep does: whether a row's number is still worth keeping,
/// and whether the sweep that is about to write is still the newest one. Both are easy to get
/// subtly wrong — a cancelled sweep that keeps its number looks current again, a profile
/// change that keeps its dates makes another subscription's rows look fresh — so they live in
/// one small pure object that tests can drive directly, and the notifier only delegates.
library;

import '../enum/enum.dart';

/// How long a measurement stays good enough to skip.
///
/// Two minutes: a node's reachability does not change in a minute, and a switch back to the
/// mode just left must not re-measure the half of the list it had just finished.
const Duration delayFreshness = Duration(minutes: 2);

/// The sweep's own record: a monotonic id, the mode it serves, and when each row was measured.
class SweepLedger {
  SweepLedger({DateTime Function()? now, Duration freshness = delayFreshness})
      : _now = now ?? DateTime.now,
        freshness = freshness;

  final DateTime Function() _now;

  /// How long a row's number stays fresh. Injected so tests do not wait two minutes.
  final Duration freshness;

  /// The newest sweep's number. It only ever grows.
  int _id = 0;

  /// The mode the newest sweep serves, or null when none is running.
  Mode? _mode;

  final Map<String, DateTime> _measuredAt = {};

  /// The newest sweep's number, for a caller that wants to remember what it started.
  int get id => _id;

  /// The mode the newest sweep serves.
  Mode? get mode => _mode;

  /// The rows that carry a number, and when.
  Map<String, DateTime> get measuredAt => Map.unmodifiable(_measuredAt);

  /// Starts a sweep for [mode] and answers its number.
  ///
  /// Starting one is what supersedes the previous: nobody else has to clear anything.
  int begin(Mode mode) {
    _id++;
    _mode = mode;
    return _id;
  }

  /// Supersedes whatever is running — a mode switch, a profile change, a new list.
  void cancel() {
    _id++;
    _mode = null;
  }

  /// True while [id] is still the newest sweep and the mode has not changed under it.
  bool isCurrent(int id, Mode mode) => _id == id && _mode == mode;

  /// Records one answer, a dash included.
  ///
  /// A dash is "asked, no answer" and counts as a measurement too: asking again inside the
  /// freshness window would only spend another timeout on a node that just refused.
  void record(String name, int? _) {
    _measuredAt[name] = _now();
  }

  /// True when [name] carries a number younger than [freshness].
  bool isFresh(String name) {
    final at = _measuredAt[name];
    if (at == null) return false;
    return _now().difference(at) < freshness;
  }

  /// Forgets everything: another profile is another subscription, and its names only look
  /// alike. The sweep in flight is superseded as well.
  void reset() {
    _measuredAt.clear();
    cancel();
  }
}
