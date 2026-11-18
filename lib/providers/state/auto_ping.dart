part of '../state.dart';

// The auto-ping switch, in the state layer: the setup action needs its period when it builds the
// child's document, and a view file cannot be imported from there.
//
// Two modes, two switches, two numbers. They look like one control on screen because the owner
// thinks of "the list in front of me", but nothing is shared: the engine's period is the engine's,
// the child's is the child's, and each is stored under its own key so a restart brings back the
// number that belonged to that mode.

/// One mode's auto-ping: whether it runs, how often, and who owns the number.
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

class AutoPingNotifier extends Notifier<AutoPingState> {
  Timer? _timer;
  VoidCallback? _tick;

  bool get _simple =>
      ref.read(patchClashConfigProvider.select((s) => s.mode)) == Mode.global;

  @override
  AutoPingState build() {
    // The mode is part of the state, not a detail of the caller: switching the portal hands the
    // control the other mode's numbers instead of carrying one mode's period into the other.
    final xray = ref.watch(patchClashConfigProvider.select((s) => s.mode)) ==
        Mode.global;
    final settings = ref.watch(appSettingProvider);
    ref.onDispose(() => _timer?.cancel());
    final built = AutoPingState(
      enabled:
          xray ? settings.portalPingXrayEnabled : settings.portalPingRulesEnabled,
      interval: Duration(
        seconds: xray
            ? settings.portalPingXrayInterval
            : settings.portalPingRulesInterval,
      ),
      asInSubscription:
          xray ? false : settings.portalPingRulesAsInSubscription,
    );
    // A timer cannot be started while the state is still being built, so the first period is
    // scheduled for the next microtask.
    if (built.enabled) {
      Future<void>.microtask(() {
        if (!ref.mounted) return;
        _restart(built.interval);
      });
    }
    return built;
  }

  AutoPingState get current => state;

  /// Applies one change from the dialog. The record and the stored setting move together, so a
  /// restart cannot bring back the previous number.
  void apply({bool? enabled, Duration? interval, bool? asInSubscription}) {
    final next = state.copyWith(
      enabled: enabled,
      interval: interval == null ? null : _clampInterval(interval),
      asInSubscription: asInSubscription,
    );
    if (next.enabled == state.enabled &&
        next.interval == state.interval &&
        next.asInSubscription == state.asInSubscription) {
      return;
    }
    state = next;
    _persist(next);
    if (next.enabled) {
      _restart(next.interval);
    } else {
      _timer?.cancel();
      _timer = null;
    }
    commonPrint.log(
      'portal auto ping (${_simple ? 'xray' : 'engine'}): '
      '${next.enabled ? 'on' : 'off'} '
      '${next.asInSubscription ? 'as in the subscription' : '${next.interval.inSeconds} s'}',
    );
  }

  /// Turns the switch on or off; [tick] is the work one period does.
  void setEnabled(bool value, {VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    apply(enabled: value);
  }

  /// The provider's own value stands; nothing is overridden. Network mode only.
  void setAsInSubscription({VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    apply(enabled: true, asInSubscription: true);
  }

  /// A period of our own: this is what turns an override on.
  void setInterval(Duration interval, {VoidCallback? tick}) {
    if (tick != null) _tick = tick;
    apply(interval: interval, asInSubscription: false);
  }

  void _persist(AutoPingState value) {
    final settings = ref.read(appSettingProvider.notifier);
    if (_simple) {
      settings.update(
        (s) => s.copyWith(
          portalPingXrayEnabled: value.enabled,
          portalPingXrayInterval: value.interval.inSeconds,
        ),
      );
      return;
    }
    settings.update(
      (s) => s.copyWith(
        portalPingRulesEnabled: value.enabled,
        portalPingRulesInterval: value.interval.inSeconds,
        portalPingRulesAsInSubscription: value.asInSubscription,
      ),
    );
  }

  void _restart(Duration period) {
    _timer?.cancel();
    _timer = Timer.periodic(period, (_) => _tick?.call());
  }
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
