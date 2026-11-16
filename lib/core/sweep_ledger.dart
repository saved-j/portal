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

  Mode? _lastMode;
  int _lastListHash = 0;
  DateTime? _lastStartedAt;

  /// Whether an automatic sweep is due: the list has never been swept, or its last sweep is
  /// older than [freshness]. Used by the repeating timer, which must not re-measure a list
  /// that was just done by the sweep at launch or after a switch.
  bool isDue(Mode mode, String listKey) => shouldStart(mode, listKey);

  /// Whether this list needs a sweep at all.
  ///
  /// A rebuild recreates the widget that asks, and a recreated widget has no memory: without
  /// this, every rebuild began a new sweep and cancelled the one in flight, so the numbers
  /// never finished arriving. The rule is the list's own: the same mode and the same names,
  /// swept less than [freshness] ago, is the sweep that is already running or just finished.
  bool shouldStart(Mode mode, String listKey) {
    final at = _lastStartedAt;
    if (at == null || _lastMode != mode || _lastListHash != listKey.hashCode) {
      return true;
    }
    return _now().difference(at) >= freshness;
  }

  /// Remembers which list was just swept, and when.
  void markStarted(Mode mode, String listKey) {
    _lastMode = mode;
    _lastListHash = listKey.hashCode;
    _lastStartedAt = _now();
  }

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

  /// Whether [name] should be measured now.
  ///
  /// [force] is a deliberate press of the test button: it measures everything in front of the
  /// owner whatever the window says. The automatic sweep passes nothing and respects it.
  bool needsMeasurement(String name, {bool force = false}) =>
      force || !isFresh(name);

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
