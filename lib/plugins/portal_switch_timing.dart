import 'dart:async';

import '../common/print.dart';
import 'portal_runtime.dart';

/// The clock one mode switch is measured with.
///
/// A switch has two moments the owner can feel: the instant the new owner holds the tunnel,
/// and the instant the list has rows again. The first is the record's own — the native side
/// stamps the tap and writes the line from the same hook that writes every transition — and
/// the second is the screen's, because only the screen knows when a row is on it. Both lines
/// land in `portal-transitions.log`, both carry `duration_ms` from the tap.
///
/// Everything here is a no-op until [begin], and each line is written at most once per tap, so
/// a screen that rebuilds sixty times a second costs one comparison and nothing else.
class PortalSwitchClock {
  PortalSwitchClock._();

  static final PortalSwitchClock instance = PortalSwitchClock._();

  Stopwatch? _watched;

  String _to = '';

  bool _listed = false;

  /// The tap, before it asks for anything: this is zero for both measurements.
  void begin({required bool toSimple}) {
    _to = toSimple ? 'global' : 'rule';
    _listed = false;
    _watched = Stopwatch()..start();
    // The native clock cannot be started from Dart's later, so it is started by the first
    // channel call the tap makes — one hop, and the record does the rest.
    unawaited(portalRuntime.beginSwitch(to: _to));
  }

  /// The first frame after the tap that has rows to draw.
  ///
  /// [source] is where they came from: the current owner's own answer (`live`), the last
  /// group the list drew (`held`), the engine's own last answer for this profile (`cache`),
  /// the profile's own `proxies:` (`profile`), or the simple portal's servers (`servers`).
  /// [mode] is the mode they were drawn in, and it is part of the line: a tap that lands in
  /// the other mode must show the other mode's names, and a number with no mode beside it
  /// cannot tell those two lists apart.
  void listPopulated({
    required String source,
    required int rows,
    required String mode,
  }) {
    final watch = _watched;
    if (watch == null || _listed) return;
    _listed = true;
    watch.stop();
    final ms = watch.elapsedMilliseconds;
    commonPrint.log(
      'portal switch: tap → $rows rows in ${ms}ms (mode=$mode source=$source)',
    );
    unawaited(
      portalRuntime.noteSwitchTiming(
        phase: 'list',
        durationMs: ms,
        detail: 'mode=$mode source=$source rows=$rows',
      ),
    );
  }

  /// The tap that did not become a switch: its clock stops without writing a length it
  /// never reached. A failed switch is reported as a failure, not as a slow list.
  void end() {
    _watched = null;
    _listed = false;
  }
}

final portalSwitchClock = PortalSwitchClock.instance;
