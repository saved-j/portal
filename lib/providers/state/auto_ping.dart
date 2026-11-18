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

  /// The provider's own value stands; nothing is overridden. Network mode only.
  void setAsInSubscription({VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    if (state.asInSubscription) return;
    state = state.copyWith(asInSubscription: true);
    _restart();
    commonPrint.log('portal auto ping: as in the subscription');
  }

  /// A period of our own: this is what turns an override on.
  void setInterval(Duration interval, {VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    final clamped = _clampInterval(interval);
    if (clamped == state.interval && !state.asInSubscription) return;
    state = state.copyWith(interval: clamped, asInSubscription: false);
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

/// Whether the list re-measures itself, how often, and who owns that number.
class AutoPingState {
  const AutoPingState({
    required this.enabled,
    required this.interval,
    this.asInSubscription = false,
  });

  final bool enabled;
  final Duration interval;

  /// "Как в подписке": the engine's own value stands and nothing is overridden.
  ///
  /// Only the network mode has such a value — a subscription carries no interval for Xray, so
  /// the switch there is the only owner of the number. Off is not the same thing as this: off
  /// means no background checks at all, this means the provider decides.
  final bool asInSubscription;

  AutoPingState copyWith({
    bool? enabled,
    Duration? interval,
    bool? asInSubscription,
  }) =>
      AutoPingState(
        enabled: enabled ?? this.enabled,
        interval: interval ?? this.interval,
        asInSubscription: asInSubscription ?? this.asInSubscription,
      );
}

// Kept alive: the timer is the switch's own state and must not be cancelled because the list
// that draws the bolt was rebuilt while a read was in flight.
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