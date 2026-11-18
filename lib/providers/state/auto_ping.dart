part of '../state.dart';

// The auto-ping switch, in the state layer: the setup action needs its period when it builds the
// child's document, and a view file cannot be imported from there.

/// The auto-ping switch of the list in front of the owner.
///
/// One control, two cores behind it — the same shape the whole dashboard has: what the owner
/// sees is one bolt, and what it drives is whatever core the list belongs to.
///
/// The number it shows is never measured by the app. mihomo keeps its own URLTEST results and
/// Xray keeps its own observatory; all this does is ask, on the owner's schedule, for them to be
/// refreshed, and hold the period he chose.
class AutoPingNotifier extends Notifier<AutoPingState> {
  Timer? _timer;
  VoidCallback? _tick;

  @override
  AutoPingState build() {
    ref.onDispose(() => _timer?.cancel());
    return const AutoPingState(enabled: true, interval: defaultAutoPingInterval);
  }

  AutoPingState get current => state;

  /// Turns the switch on or off; [tick] is the work one period does.
  void setEnabled(bool value, {VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    if (state.enabled == value) return;
    state = state.copyWith(enabled: value);
    _restart();
    commonPrint.log(
      'portal auto ping: ${value ? 'on' : 'off'} every ${state.interval.inSeconds} s',
    );
  }

  /// Changes the period and keeps the switch as it is.
  void setInterval(Duration interval, {VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    final clamped = _clampInterval(interval);
    if (clamped == state.interval) return;
    state = state.copyWith(interval: clamped);
    if (state.enabled) _restart();
    commonPrint.log('portal auto ping: interval ${clamped.inSeconds} s');
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (!state.enabled) return;
    _timer = Timer.periodic(state.interval, (_) => _tick?.call());
  }
}

/// Whether the list re-measures itself, and how often.
class AutoPingState {
  const AutoPingState({required this.enabled, required this.interval});

  final bool enabled;
  final Duration interval;

  AutoPingState copyWith({bool? enabled, Duration? interval}) => AutoPingState(
        enabled: enabled ?? this.enabled,
        interval: interval ?? this.interval,
      );
}

final autoPingProvider =
    NotifierProvider<AutoPingNotifier, AutoPingState>(AutoPingNotifier.new);

/// Default period. The same order as mihomo's own url-test clock, but chosen for what the
/// owner reads, not for what a balancer needs: a minute is short enough that a dead node is
/// noticed while he is still looking at it.
const defaultAutoPingInterval = Duration(seconds: 60);

/// The period is the owner's, within reason: below [minAutoPingInterval] it is the phone's
/// battery paying for a number nobody can read faster than it changes, above
/// [maxAutoPingInterval] the figure is stale before it is drawn.
const minAutoPingInterval = Duration(seconds: 30);
const maxAutoPingInterval = Duration(minutes: 5);

Duration _clampInterval(Duration value) {
  if (value < minAutoPingInterval) return minAutoPingInterval;
  if (value > maxAutoPingInterval) return maxAutoPingInterval;
  return value;
}