import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/proxies/proxies.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fl_clash/common/outbound.dart';
import 'package:fl_clash/core/proxy_endpoints.dart';
import 'package:fl_clash/core/xray_ping.dart';
import 'package:fl_clash/core/xray_subscription.dart';
import '../profiles/subscription_facts.dart';
import 'package:fl_clash/plugins/xray.dart';
import 'package:yaml/yaml.dart';
import 'dart:async';
import 'dart:convert';

/// How the server list is ordered; the switch sits next to the mode control.
enum PortalSort {
  /// The panel's own order, which is often the order the owner paid for.
  subscription,
  ping,
  alphabet,
}

extension PortalSortExt on PortalSort {
  String get label => switch (this) {
        PortalSort.subscription => 'asInSubscription',
        PortalSort.ping => 'byPing',
        PortalSort.alphabet => 'byName',
      };

  PortalSort get next => switch (this) {
        PortalSort.subscription => PortalSort.ping,
        PortalSort.ping => PortalSort.alphabet,
        PortalSort.alphabet => PortalSort.subscription,
      };
}

/// The order of the server list, kept per mode.
///
/// The two modes show different servers from different builds of the same subscription, and
/// the owner wants them ordered differently: rules by ping, the simple portal as the panel
/// sent it. One stored value per mode, so switching never rewrites the other's choice.
class PortalSortNotifier extends Notifier<PortalSort> {
  bool get _simple =>
      ref.read(patchClashConfigProvider.select((s) => s.mode)) == Mode.global;

  @override
  PortalSort build() {
    // Watched, so flipping the switch re-reads the other mode's stored order.
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final settings = ref.watch(appSettingProvider);
    final stored = mode == Mode.global ? settings.portalSortXray : settings.portalSortRules;
    return PortalSort.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => PortalSort.subscription,
    );
  }

  void cycle() {
    final next = state.next;
    ref.read(appSettingProvider.notifier).update(
          (settings) => _simple
              ? settings.copyWith(portalSortXray: next.name)
              : settings.copyWith(portalSortRules: next.name),
        );
  }
}

final portalSortProvider =
    NotifierProvider<PortalSortNotifier, PortalSort>(PortalSortNotifier.new);

/// The server picked in each mode, kept apart and keyed by profile.
///
/// The two lists are different builds of one subscription: the rules list names the
/// engine's servers, the simple portal names the child's, and a name picked in one means
/// nothing in the other. One stored pick for both would move the highlight onto a server
/// that is not in the list — and one stored pick for every profile moved it onto a server
/// that is not in *this* subscription at all.
///
/// The pick of the child's node is a commit, not a hope: it is written only after the child
/// acknowledged the tunnel, so what this list highlights is always what the child runs.
class PortalSelectionNotifier
    extends Notifier<({Map<String, String> rules, String xray})> {
  @override
  ({Map<String, String> rules, String xray}) build() {
    final settings = ref.watch(appSettingProvider);
    final profileId = ref.watch(currentProfileIdProvider);
    return (
      rules: portalRulePicksFor(settings, profileId),
      xray: portalXrayPickFor(settings, profileId),
    );
  }

  /// A filter's pick in the rules list, written beside the engine's own selection: the
  /// engine answers for itself, and this is what the list falls back to when it does not.
  void pickRule(String group, String proxy) {
    final profileId = ref.read(currentProfileIdProvider);
    final settings = withPortalRulePick(
      ref.read(appSettingProvider),
      profileId,
      group,
      proxy,
    );
    state = (
      rules: portalRulePicksFor(settings, profileId),
      xray: portalXrayPickFor(settings, profileId),
    );
    ref.read(appSettingProvider.notifier).update((_) => settings);
  }

  /// The Xray node the child runs, written only once the child has taken the tunnel.
  void pickXray(String proxy, {int? profileId}) {
    final profile = profileId ?? ref.read(currentProfileIdProvider);
    if (portalXrayPickFor(ref.read(appSettingProvider), profile) == proxy) {
      return;
    }
    final settings = withPortalXrayPick(
      ref.read(appSettingProvider),
      profile,
      proxy,
    );
    state = (
      rules: portalRulePicksFor(settings, profile),
      xray: portalXrayPickFor(settings, profile),
    );
    ref.read(appSettingProvider.notifier).update((_) => settings);
  }
}

final portalSelectionProvider = NotifierProvider<PortalSelectionNotifier,
    ({Map<String, String> rules, String xray})>(PortalSelectionNotifier.new);

/// Which group the strip shows. Null means "the first one the panel offers",
/// which survives subscription updates that reorder groups.
class PortalGroupNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void pick(String? name) => state = name;
}

final portalGroupProvider =
    NotifierProvider<PortalGroupNotifier, String?>(PortalGroupNotifier.new);

/// The row the user just tapped. The engine may take a moment to switch, so the
/// highlight moves at once and this clears when the group reports the same choice.
class PortalPendingNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void pick(String group, String proxy) => state = {...state, group: proxy};

  void clear(String group) {
    if (!state.containsKey(group)) return;
    state = {...state}..remove(group);
  }
}

final portalPendingProvider =
    NotifierProvider<PortalPendingNotifier, Map<String, String>>(
        PortalPendingNotifier.new);

/// Delays timed by the app itself, for servers of either core.
///
/// The engine only reports delays for the servers it holds and never their addresses, so a
/// TCP handshake from here is the one measurement that works for both lists. A missing key
/// means "not asked yet"; a null entry means "asked, no answer".
final tcpDelayProvider =
    NotifierProvider<TcpDelayNotifier, Map<String, int?>>(TcpDelayNotifier.new);

/// The addresses saved with the profile, so an engine server can be timed directly.
final proxyEndpointsProvider =
    FutureProvider.autoDispose<Map<String, ProxyEndpoint>>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const {};
  final path = await appPath.getProfilePath(profile.id.toString());
  return loadProxyEndpoints(path);
});

class TcpDelayNotifier extends Notifier<Map<String, int?>> {
  /// Handshakes open at once. A panel list is often a hundred nodes and one unreachable
  /// node costs the full timeout, so a serial sweep holds the screen for minutes.
  static const _parallel = 8;

  /// Bumped by every sweep, and by a profile change. An answer arriving under an older
  /// number belongs to servers the list no longer shows — usually names that repeat in the
  /// new subscription — so it is dropped instead of written under the current key.
  int _generation = 0;

  @override
  Map<String, int?> build() {
    // The measurements belong to the profile: a different one is a different set of
    // servers, so the map goes with it instead of lighting up names that only look alike.
    ref.watch(currentProfileIdProvider);
    ref.onDispose(() => _generation++);
    return const {};
  }

  Future<void> measureAll(List<(String, String, int)> targets) async {
    if (targets.isEmpty) return;
    // A newer sweep owns the state from here on; the older one stops at its next answer.
    final generation = ++_generation;
    state = {...state, for (final t in targets) t.$1: null};
    var next = 0;
    Future<void> worker() async {
      while (true) {
        // Checked before taking work as well as after answering: a cancelled sweep must not
        // keep opening handshakes for a list that is no longer on screen.
        if (generation != _generation) return;
        final index = next++;
        if (index >= targets.length) return;
        final (name, host, port) = targets[index];
        final value = await tcpPing(host, port);
        if (generation != _generation) return;
        state = {...state, name: value};
      }
    }

    await Future.wait([
      for (var i = 0; i < _parallel && i < targets.length; i++) worker(),
    ]);
  }

  Future<void> measureOne(String name, String host, int port) async {
    final generation = _generation;
    state = {...state, name: null};
    final value = await tcpPing(host, port);
    if (generation != _generation) return;
    state = {...state, name: value};
  }

  /// Revokes every sweep in flight, for a list that is gone or has been replaced.
  ///
  /// Whoever started the work can stop it being written: the workers compare the generation
  /// they started under with the current one, so an answer that arrives after the list was
  /// disposed is dropped instead of lighting up a row nobody is looking at.
  void cancel() => _generation++;
}

/// Groups the user turned into a bypass: their outbound is DIRECT, so the chip can
/// simply go grey. The name people know for that state is 'не идёт через портал'.
class PortalBypassNotifier extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() => const {};

  /// Drops the remembered state without touching the proxy — used when the user picks a
  /// portal by hand for a filter that was out of the portal from the start.
  void forget(String name) {
    if (!state.containsKey(name)) return;
    state = {...state}..remove(name);
  }

  /// The press answers in the UI at once; the engine is told afterwards and its answer
  /// is not waited for. A chip that greys only when the core confirms reads as a dead
  /// control, and the user's job is not to watch the tunnel.
  void toggle(WidgetRef ref, Group group) {
    final action = ref.read(proxiesActionProvider.notifier);
    if (state.containsKey(group.name)) {
      final restore = state[group.name];
      state = {...state}..remove(group.name);
      if (restore != null) {
        action.changeProxy(groupName: group.name, proxyName: restore);
      }
      return;
    }
    // Bypass routes to the engine's own built-in, whatever the panel calls it.
    final target = group.all
            .where((proxy) => _isBuiltinOutbound(proxy.name))
            .map((proxy) => proxy.name)
            .firstOrNull ??
        'DIRECT';
    state = {...state, group.name: group.now};
    action.changeProxy(groupName: group.name, proxyName: target);
  }
}

final portalBypassProvider =
    NotifierProvider<PortalBypassNotifier, Map<String, String?>>(
        PortalBypassNotifier.new);

/// How the filter chips are drawn. Default 2 is 'name + server + icon'. Lives in a
/// provider so switching the mode does not reset the user's choice.
class PortalDisplayNotifier extends Notifier<int> {
  @override
  int build() => 2;

  void cycle() => state = (state + 1) % 5;
}

final portalDisplayProvider =
    NotifierProvider<PortalDisplayNotifier, int>(PortalDisplayNotifier.new);


/// What is actually crossing the wire right now: how many connections are open, and how
/// fast the wire moves, taken from the engine's own answers. Nothing here is inferred or
/// animated for show.
typedef PortalLive = ({
  int connections,
  int down,
  int up,
});

/// The rate comes from the traffic sample, not from the connection list.
///
/// The engine's connection snapshot carries cumulative totals per connection and no rate at
/// all — `downloadSpeed`/`uploadSpeed` on a tracked connection are read here and written
/// nowhere in the app, so summing them answered a hard zero however fast the wire moved.
/// The engine does report a rate, once a second, in the traffic sample the speed widgets
/// already draw from; that is the same number the tray title shows, so the portal and the
/// cards now agree instead of one of them standing still.
final portalLiveProvider = Provider<PortalLive>((ref) {
  final connections = ref.watch(requestsProvider.select((state) => state.length));
  final sample = ref.watch(
    trafficsProvider.select((state) => state.list.safeLast(const Traffic())),
  );
  return (
    connections: connections,
    down: sample.down.round(),
    up: sample.up.round(),
  );
});

class PortalFiltersNotifier extends Notifier<({Set<String> hidden, List<String> order})> {
  @override
  ({Set<String> hidden, List<String> order}) build() =>
      (hidden: <String>{}, order: const <String>[]);

  void toggle(String name) {
    final hidden = {...state.hidden};
    if (!hidden.remove(name)) hidden.add(name);
    state = (hidden: hidden, order: state.order);
  }

  void reorder(List<String> order) =>
      state = (hidden: state.hidden, order: order);

}

final portalFiltersProvider = NotifierProvider<PortalFiltersNotifier,
    ({Set<String> hidden, List<String> order})>(PortalFiltersNotifier.new);

/// The engine's built-in outbounds sometimes arrive decorated ('DIRECT 🇷🇺',
/// 'Direct '), so the check is on the leading word, not on an exact match.
bool _isBuiltinOutbound(String name) => isBuiltinOutboundName(name);

List<Group> portalGroups(List<Group> all) => [
      for (final item in all)
        if (item.hidden != true && !_isBuiltinOutbound(item.name)) item,
    ];

/// Same list, after the user's own order and hidden set.
List<Group> portalVisibleGroups(List<Group> all, Set<String> hidden, List<String> order) {
  final visible = [
    for (final group in portalGroups(all))
      if (!hidden.contains(group.name)) group,
  ];
  if (order.isEmpty) return visible;
  // One index per name, built once: the comparator used to scan the whole order list twice
  // per comparison, and this function runs inside the builders of the panel — a hundred
  // filters made the sort the most expensive thing in a frame.
  final rank = <String, int>{
    for (final (index, name) in order.indexed) name: index,
  };
  visible.sort((a, b) {
    final ia = rank[a.name] ?? -1;
    final ib = rank[b.name] ?? -1;
    if (ia == -1 && ib == -1) return 0;
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return visible;
}

/// The name of the one group the simple portal draws when no engine serves one.
const portalSimpleGroupName = 'PORTAL';

/// A group for the child's own server list.
///
/// The list, the row and the mode control are all shaped around a [Group], and in the simple
/// portal no engine holds one: this is the group the child's servers make — a selector whose
/// members are the nodes the panel offered and whose `now` is the node the child runs. It is
/// never written to the engine; it exists so the same widgets can draw a list with no engine
/// behind it.
Group simplePortalGroup(List<XrayServerConfig> servers, {String? now}) => Group(
      type: GroupType.Selector,
      name: portalSimpleGroupName,
      now: now,
      all: [
        for (final server in servers)
          Proxy(
            name: server.name,
            type: server.protocol,
            serverDescription: server.label,
          ),
      ],
    );

/// The servers the second core offers.
///
/// The subscription body is an array of full xray configurations and each element is one
/// server, so the list is built from those elements — name, description and the config that
/// would be started if it were chosen.
final xrayServersProvider =
    FutureProvider.autoDispose<List<XrayServerConfig>>((ref) async {
  final profile = ref.read(currentProfileProvider);
  if (profile == null) return const [];
  final body = await profile.readXrayFormat();
  if (body == null) return const [];
  final parsed = parseXraySubscriptionResult(body);
  final servers = parsed.servers;
  // `ok` is the parse's own verdict, not a second guess at `servers.isNotEmpty`: the two
  // agree today, and this is the one place that decides which of the two lines below runs.
  if (parsed.ok) {
    commonPrint.log(
      'xray subscription: ${servers.length} servers, '
      'first=${servers.take(3).map((s) => s.label).join(' | ')}',
    );
  } else if (parsed.problem != null) {
    // An empty list is three different answers — an unreadable body, another schema, or a
    // subscription with no nodes — so the reason is reported with the profile it was read
    // for instead of dying in a bare `[]`.
    commonPrint.log(
      'xray subscription unreadable: profile=${profile.id} ${parsed.message}',
      logLevel: LogLevel.warning,
    );
  }
  return servers;
});

/// What the subscription's engine-format file actually answered.
///
/// Three states, because a corrupt file and an absent one are different problems: the first
/// is a download the owner can fix by updating the profile, the second is a panel that does
/// not serve this format at all. Collapsing both into `false` — which a blanket `catch (_)`
/// did — hid the first behind the second.
enum EngineFormatStatus {
  /// The file reads and carries a config.
  ok,

  /// The file is there but could not be read: a corrupt or half-written download.
  parseFailed,

  /// No such file, or nothing in it: this panel does not serve the engine's format.
  empty,
}

/// What the check found, and why it is not usable when it is not.
typedef EngineFormatCheck = ({EngineFormatStatus status, String reason});

/// The first thing that makes [document] unusable as the rules list, or null.
///
/// The size of the file says nothing about its shape: a 200-byte error page downloaded in
/// place of the config is larger than 32 bytes and reads as "ok" to a length check, and the
/// switch then opens a portal with no rules in it. The minimum shape is a proxy source
/// (`proxies` or `proxy-providers`) and a rules key; anything else is a file this mode
/// cannot use, and the reason names which half is missing.
String? engineFormatProblem(Object? document) {
  if (document is! Map) return 'the file is not a mapping';
  final proxies = document['proxies'];
  final providers = document['proxy-providers'];
  final hasProxies = proxies is List && proxies.isNotEmpty;
  final hasProviders = providers is Map && providers.isNotEmpty;
  if (!hasProxies && !hasProviders) {
    return 'no proxies or proxy-providers';
  }
  final rules = document['rules'];
  final subRules = document['sub-rules'];
  if (rules is! List && subRules is! List) return 'no rules';
  return null;
}

/// Whether the current subscription carries a config the rules mode can use.
///
/// The "Сеть порталов" switch is meaningless without one: rules live in that YAML, and a
/// subscription the panel only serves for Xray has nothing to route. Unknown counts as
/// available so the switch does not flicker off while the file is being checked.
final engineFormatStatusProvider =
    FutureProvider.autoDispose<EngineFormatCheck>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) {
    return (status: EngineFormatStatus.empty, reason: 'no profile is selected');
  }
  try {
    final file = await profile.file;
    if (!await file.exists()) {
      return (status: EngineFormatStatus.empty, reason: 'the file is missing');
    }
    final text = await file.readAsString();
    if (text.trim().isEmpty) {
      return (status: EngineFormatStatus.empty, reason: 'the file is empty');
    }
    // Parsed, not measured: a downloaded error page has a size and no config.
    final problem = engineFormatProblem(loadYaml(text));
    if (problem != null) {
      commonPrint.log(
        'engine format is not a config: $problem',
        logLevel: LogLevel.warning,
      );
      return (status: EngineFormatStatus.parseFailed, reason: problem);
    }
    return (status: EngineFormatStatus.ok, reason: '');
  } catch (error) {
    // The reason goes to the log that already carries the core's own faults: a corrupt
    // subscription is a fact about the download, and it must not read as "no rules here".
    final reason = compactError(error);
    commonPrint.log(
      'engine format read failed: $reason',
      logLevel: LogLevel.warning,
    );
    return (status: EngineFormatStatus.parseFailed, reason: reason);
  }
});

/// Puts the portal into the simple mode.
///
/// Only the mode moves here: in this mode the tunnel is the Xray child's, made by the
/// service when the portal starts, and there is no engine config to build and no proxy of
/// the engine's to point anywhere. The child itself is started by the run that follows, on
/// the node this list shows, and only reports success once it has acknowledged the tunnel.
///
/// The answer is the mode's own: a mode that is not offered, or a take-over the owner
/// declined, comes back as a cancellation the transaction can report instead of a step it
/// assumes happened.
Future<PortalCoreResult> _enterSimplePortal(WidgetRef ref) async {
  return ref.read(setupActionProvider.notifier).pickMode(Mode.global);
}

/// Mode control with the two list controls beside it: sorting and the delay test.
class PortalModeSwitch extends ConsumerWidget {
  const PortalModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final modes = ref.watch(availableModesProvider);
    final running = ref.watch(runTimeProvider) != null;
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(
      ref.watch(groupsProvider),
      filters.hidden,
      filters.order,
    );
    final groupName = ref.watch(portalGroupProvider);
    final simple = mode == Mode.global;
    final xrayServers = simple
        ? (ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[])
        : const <XrayServerConfig>[];
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull ??
        (xrayServers.isEmpty ? null : simplePortalGroup(xrayServers));
    final sort = ref.watch(portalSortProvider);
    final engineCheck = ref.watch(engineFormatStatusProvider).value;
    final engineFormat = engineCheck?.status ?? EngineFormatStatus.ok;
    final engineAvailable = engineFormat == EngineFormatStatus.ok;
    final engineReason = engineCheck?.reason ?? '';
    final testing = group != null &&
        ref.watch(
          delayTestingGroupsProvider.select((s) => s.contains(group.name)),
        );
    if (modes.length < 2) return const SizedBox.shrink();
    return Row(
      children: [
        // Switch at the left edge, its label to the right of it.
        // Centred pair: a larger label in the legacy green while the network is on,
        // and a switch that reads as a switch. The editor button only exists in the
        // network mode, so 'Сеть порталов' has somewhere obvious to lead.
        GestureDetector(
          // A plain tap on 'Сеть порталов' opens the proxies dashboard: that is what
          // the network mode is for. The double tap still edits the filter strip.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ProxiesView()),
          ),

          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A dead switch says why it is dead: the reason is the file's own, carried
              // from the check that refused it instead of a generic "unavailable".
              Tooltip(
                message: engineAvailable
                    ? ''
                    : context.appLocalizations.engineFormatUnusable(
                        engineReason,
                      ),
                child: Switch(
                  value: mode == Mode.rule && engineAvailable,
                  activeThumbColor: _liveGreen(context),
                  activeTrackColor: _liveGreen(context).withValues(alpha: 0.4),
                  // No engine format, no rules: the control stays visible but dead, so the
                  // owner sees why instead of a switch that does nothing.
                  onChanged: !engineAvailable
                      ? null
                      : (value) {
                          HapticFeedback.selectionClick();
                          // The thumb has already moved; the portal underneath either
                          // comes up on the other core or comes back exactly as it was.
                          unawaited(
                            _switchPortal(ref, toSimple: !value),
                          );
                        },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.appLocalizations.rules,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: mode == Mode.rule
                      ? _liveGreen(context)
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        const SizedBox(width: 4),
        IconButton(
          tooltip: context.appLocalizations.sortTooltip(sortLabelFor(context, sort)),
          onPressed: () {
            HapticFeedback.selectionClick();
            ref.read(portalSortProvider.notifier).cycle();
          },
          icon: GlyphIcon(
            switch (sort) {
              PortalSort.subscription => AppGlyphs.sliders,
              PortalSort.ping => AppGlyphs.sort,
              PortalSort.alphabet => AppGlyphs.textShort,
            },
            size: 18,
          ),
        ),
        IconButton(
          tooltip: context.appLocalizations.delayTest,
          // A delay test says which servers answer, so it must not depend on the portal
          // being open: the test wakes the engine for its duration and closes it again.
          onPressed: testing
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  // In the simple portal the list is the second core's, so the engine test
                  // has nothing to measure — its own servers are timed directly instead.
                  // The app's own measurement serves both lists; the engine test is the
                  // fallback for a profile whose addresses are unknown.
                  final servers = ref.read(xrayServersProvider).value ?? const [];
                  final endpoints = ref.read(proxyEndpointsProvider).value ?? const {};
                  final targets = <(String, String, int)>[
                    for (final server in servers)
                      if (server.port > 0) (server.name, server.address, server.port),
                    if (servers.isEmpty && group != null)
                      for (final proxy in group.all)
                        if (endpoints[proxy.name] case final e? when e.isUsable)
                          (proxy.name, e.host, e.port),
                  ];
                  if (targets.isNotEmpty) {
                    unawaited(
                      ref.read(tcpDelayProvider.notifier).measureAll(targets),
                    );
                    return;
                  }
                  if (group == null) return;
                  unawaited(
                    _testDelayWithEngine(
                      ref,
                      [
                        for (final proxy in group.all)
                          if (!_isBuiltinOutbound(proxy.name)) proxy,
                      ],
                      testUrl: group.testUrl,
                      wasRunning: running,
                    ),
                  );
                },
          // A test in flight spins instead of pretending nothing is happening.
          icon: testing
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              : GlyphIcon(
                  AppGlyphs.bolt,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ],
    );
  }
}

/// The working screen's server list: a group strip with arrows (network mode only),
/// a tinted row for the chosen server, name left and delay right.
class PortalServerList extends ConsumerWidget {
  const PortalServerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(patchClashConfigProvider.select((s) => s.mode));
    final simple = mode == Mode.global;
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(
      ref.watch(groupsProvider),
      filters.hidden,
      filters.order,
    );
    final groupName = ref.watch(portalGroupProvider);
    // The simple portal is driven by the child, whose build of the same subscription names
    // its own servers. With no engine running there is no group to take them from either,
    // so the list is given a group of its own: the rows need one, and inventing none would
    // show an empty portal over a list that is not empty.
    final xrayServers = simple
        ? (ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[])
        : const <XrayServerConfig>[];
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull ??
        (xrayServers.isEmpty ? null : simplePortalGroup(xrayServers));
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.appLocalizations.proxyGroupEmpty,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final sort = ref.watch(portalSortProvider);
    final pending = ref.watch(portalPendingProvider)[group.name];
    if (pending != null && group.now == pending) {
      // Applied for real: drop the optimistic marker on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(portalPendingProvider.notifier).clear(group.name);
      });
    }
    // Two picks, one list each: the engine's own selection lights the rules list, and the
    // child's stored node lights the simple portal. The engine's answer belongs to another
    // build of the subscription, so it must not move the highlight on this one.
    final bypassedGroup = ref.watch(portalBypassProvider).containsKey(group.name);
    final chosenName = ref.watch(selectedProxyNameProvider(group.name));
    final selection = ref.watch(portalSelectionProvider);
    final xrayPick = selection.xray;
    final rulesPick = selection.rules[group.name];
    final xrayPicked =
        xrayServers.any((server) => server.name == xrayPick) ? xrayPick : null;
    final selectedName = bypassedGroup
        ? null
        : xrayServers.isNotEmpty
            ? xrayPicked
            : (pending ?? chosenName ?? rulesPick);
    // Measure once when the list arrives: a portal whose servers all read "—" until you
    // press something looks broken, and a closed portal is no reason not to know.
    final endpoints = ref.watch(proxyEndpointsProvider).value ?? const {};
    final targets = <(String, String, int)>[
      for (final server in xrayServers)
        if (server.port > 0) (server.name, server.address, server.port),
      if (xrayServers.isEmpty)
        for (final proxy in group.all)
          if (endpoints[proxy.name] case final endpoint? when endpoint.isUsable)
            (proxy.name, endpoint.host, endpoint.port),
    ];
    final xrayServerByName = {
      for (final server in xrayServers) server.name: server,
    };
    final members = xrayServers.isNotEmpty
        ? [
            for (final server in xrayServers)
              Proxy(
                name: server.name,
                // The row shows this as the protocol badge: it comes from the server's own
                // configuration, not from the fact that Xray is the core running it.
                type: server.protocol,
                serverDescription: server.label,
              ),
          ]
        : [
            for (final proxy in group.all)
              if (!_isBuiltinOutbound(proxy.name)) proxy,
          ];
    switch (sort) {
      case PortalSort.subscription:
        // The panel's order is the order it wants: leave it exactly as delivered.
        break;
      case PortalSort.alphabet:
        members.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case PortalSort.ping:
        // Ranked once per server, before the comparison. A comparator runs O(n log n)
        // times and each call used to subscribe to another provider, so the order depended
        // on which family member happened to be created first — and the subscriptions
        // outlived the sort.
        final xrayDelays = ref.watch(tcpDelayProvider);
        final ranks = <String, int>{};
        for (final proxy in members) {
          final value = xrayServerByName.containsKey(proxy.name)
              ? xrayDelays[proxy.name]
              : ref.read(delayProvider(proxyName: proxy.name));
          // -1 is mihomo's timeout marker, not a fast server.
          ranks[proxy.name] = value == null || value <= 0 ? 1 << 30 : value;
        }
        members.sort(
          (a, b) =>
              (ranks[a.name] ?? 1 << 30).compareTo(ranks[b.name] ?? 1 << 30),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Measures the servers of this list once, from a lifecycle method: a build pass is
        // not the place to start work, and a rebuild is not a reason to start it again.
        _TcpDelaySweep(targets),
        // The filter strip belongs to the engine's rules. In the simple portal the list is
        // the second core's own servers, so there are no filters to show.
        if (!simple && xrayServers.isEmpty && groups.length > 1) const _GroupStrip(),
        if (!simple && groups.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(
              group.name,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final proxy in members)
          _ServerRow(
            group: group,
            proxy: proxy,
            selected: selectedName == proxy.name,
            // Present only on the child's list: the row then knows a tap starts that node
            // instead of asking the engine for a proxy it does not have.
            xrayServer: xrayServerByName[proxy.name],
            tcpHost: xrayServerByName[proxy.name]?.address ??
                endpoints[proxy.name]?.host ??
                '',
            tcpPort: xrayServerByName[proxy.name]?.port ??
                endpoints[proxy.name]?.port ??
                0,
          ),
      ],
    );
  }
}

/// Starts the child on one server of the simple portal's list.
///
/// The tap is a restart of the child alone: its configuration names the node, the tunnel it
/// reads stays exactly where the service put it, and no proxy in any engine changes. The
/// plugin stops the previous process before starting the next, so this is also the correct
/// call while the child is already running.
///
/// The answer is the child's: `ok` only when it acknowledged the tunnel, and its own last
/// line otherwise. A refused node leaves nothing of the previous one alive, so the caller
/// must put the previous pick back — this function only reports what happened.
Future<PortalCoreResult> _restartChildOn(XrayServerConfig server) async {
  final started = await XrayCore.instance.start(jsonEncode(server.config));
  if (started.ok) {
    commonPrint.log('xray is reading the tunnel on ${server.name}');
    return started;
  }
  commonPrint.log(
    'xray restart on ${server.name} failed: ${started.reason}',
    logLevel: LogLevel.warning,
  );
  return started;
}


/// Starts the child for a row the owner tapped, and says what happened when it refuses.
///
/// The pick is written only after the child answered — a name stored before the start is a
/// pick the child never ran, which is what made a refused selection look applied. A refused
/// node is not left standing alone either: the node that was confirmed before it is started
/// again, and the reason is reported either way.
Future<void> _startFromList(WidgetRef ref, XrayServerConfig server) async {
  final profileId = ref.read(currentProfileIdProvider);
  final previous = ref.read(portalSelectionProvider).xray;
  // A closed portal has no child to restart, but the tap still chooses the node the next open
  // runs: storing the pick is the whole action, and the list highlights it immediately because
  // the highlight reads the same stored pick.
  if (ref.read(runTimeProvider) == null) {
    ref
        .read(portalSelectionProvider.notifier)
        .pickXray(server.name, profileId: profileId);
    commonPrint.log('portal will open on ${server.name}');
    return;
  }
  final started = await _restartChildOn(server);
  if (started.ok) {
    ref
        .read(portalSelectionProvider.notifier)
        .pickXray(server.name, profileId: profileId);
    return;
  }
  final restored = await _restoreXrayNode(ref, previous);
  _reportPortalFailure(
    restored
        ? started.reason
        : '${started.reason}; the previous node did not come back either',
  );
}

/// Starts the node that was confirmed before a refused one, so the portal keeps carrying.
Future<bool> _restoreXrayNode(WidgetRef ref, String name) async {
  if (name.isEmpty) return false;
  final servers = ref.read(xrayServersProvider).value ?? const <XrayServerConfig>[];
  final server = xrayServerFor(servers, name);
  if (server == null) return false;
  final restored = await _restartChildOn(server);
  return restored.ok;
}

/// The failure as a sentence, in the app's own log and on the screen.
void _reportPortalFailure(String reason) {
  commonPrint.log('portal did not start: $reason', logLevel: LogLevel.error);
  dialogs.showNotifier(
    currentAppLocalizations.portalStartFailed(reason),
    level: MessageLevel.error,
  );
}

/// Same list, same question: records compare by value, so a rebuild that recomputes the
/// targets does not throw away half-finished answers by looking like a new list.
bool _sameTargets(
  List<(String, String, int)> a,
  List<(String, String, int)> b,
) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

/// Starts one delay sweep for the servers the list is showing.
///
/// From a lifecycle method, not the build pass: a widget can be rebuilt many times a frame
/// for reasons that have nothing to do with the servers, and starting the measurement there
/// restarted it on every rebuild while the map was still empty. The sweep itself owns its
/// cancellation — a newer list bumps the generation inside the notifier, which drops the
/// answers of the older one.
class _TcpDelaySweep extends ConsumerStatefulWidget {
  const _TcpDelaySweep(this.targets);

  final List<(String, String, int)> targets;

  @override
  ConsumerState<_TcpDelaySweep> createState() => _TcpDelaySweepState();
}

class _TcpDelaySweepState extends ConsumerState<_TcpDelaySweep> {
  List<(String, String, int)>? _asked;

  @override
  void initState() {
    super.initState();
    _start(widget.targets);
  }

  @override
  void didUpdateWidget(covariant _TcpDelaySweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _start(widget.targets);
  }

  void _start(List<(String, String, int)> targets) {
    if (targets.isEmpty) return;
    final asked = _asked;
    if (asked != null && _sameTargets(asked, targets)) return;
    _asked = targets;
    unawaited(ref.read(tcpDelayProvider.notifier).measureAll(targets));
  }

  @override
  void dispose() {
    // The sweep belongs to this list. Leaving it revokes the answers still in flight: a
    // handshake that lands after the list is gone must not write a delay for a row the next
    // list never asked about.
    ref.read(tcpDelayProvider.notifier).cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Waits until the engine reports a running proxy, so the first test is not queued into a
/// core that has not applied its config yet.
Future<void> _waitForEngine(WidgetRef ref) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    if (ref.read(runTimeProvider) != null) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// Runs a delay test, opening the engine for it when the portal is closed.
///
/// The engine answers a delay test for any proxy in its applied config, but it needs to be
/// running to have that config and to reach the nodes. So a closed portal is opened for the
/// duration of the test, without any of the portal's own animation or state, and closed
/// again afterwards. If the portal was already open, nothing is toggled.
Future<void> _testDelayWithEngine(
  WidgetRef ref,
  List<Proxy> proxies, {
  String? testUrl,
  required bool wasRunning,
}) async {
  if (proxies.isEmpty) return;
  if (wasRunning) {
    await ref.read(proxiesActionProvider.notifier).delayTest(proxies, testUrl);
    return;
  }
  final testing = ref.read(delayTestingGroupsProvider.notifier);
  try {
    // Opened behind the scenes: the portal's own button and timer never see this state.
    await ref.read(setupActionProvider.notifier).setRunning(true);
    await _waitForEngine(ref);
    await ref.read(proxiesActionProvider.notifier).delayTest(proxies, testUrl);
  } finally {
    await ref.read(setupActionProvider.notifier).setRunning(false);
    testing.stop('');
  }
}

/// Horizontal group filter. The chevrons are hints, not buttons: they say the strip
/// can be dragged and hide themselves once that direction is exhausted. A double tap
/// reveals an icon on every filter — a hidden trick, not a visible control.
class _GroupStrip extends ConsumerStatefulWidget {
  const _GroupStrip();

  @override
  ConsumerState<_GroupStrip> createState() => _GroupStripState();
}

class _GroupStripState extends ConsumerState<_GroupStrip> {
  final _controller = ScrollController();
  var _canBack = false;
  var _canForward = false;


  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncEdges);
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final back = position.pixels > position.minScrollExtent + 1;
    final forward = position.pixels < position.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allGroups = ref.watch(groupsProvider);
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalVisibleGroups(allGroups, filters.hidden, filters.order);
    final display = ref.watch(portalDisplayProvider);
    final active = ref.watch(portalGroupProvider) ?? groups.firstOrNull?.name;
    final bypassedNames = ref.watch(portalBypassProvider).keys.toSet();
    final pendingByGroup = ref.watch(portalPendingProvider);
    final hint = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    return Row(
      children: [
        // Leftmost control of the strip: tap for the filter editor, hold for the
        // proxies dashboard. Sorting lives on its own button and is not repeated here.
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            showPortalFilterEditor(context);
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProxiesView()),
            );
          },
          child: const Padding(
            padding: EdgeInsets.only(right: 6),
            child: GlyphIcon(AppGlyphs.sliders, size: 20),
          ),
        ),
        SizedBox(
          width: 18,
          child: _canBack
              ? GlyphIcon(AppGlyphs.chevronBack, size: 14, color: hint)
              : null,
        ),
        Expanded(
          child: GestureDetector(
            onDoubleTap: () {
              // Changing the layout re-measures every chip; keep the strip where the
              // user left it instead of snapping back to the first one.
              final offset = _controller.hasClients ? _controller.offset : 0.0;
              ref.read(portalDisplayProvider.notifier).cycle();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_controller.hasClients) return;
                final max = _controller.position.maxScrollExtent;
                _controller.jumpTo(offset.clamp(0.0, max));
              });
            },
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _syncEdges();
                return false;
              },
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in groups)
                      Builder(builder: (context) {
                        // A filter the panel already routes to DIRECT is a bypass by
                        // definition: it should look that way before anyone touches it.
                        // A hand-picked server wins over the panel's DIRECT at once:
                        // the chip colours the moment the user chooses, without
                        // waiting for the engine to confirm the route.
                        final picked = pendingByGroup[item.name] != null;
                        final bypassed = bypassedNames.contains(item.name) ||
                            (_isBuiltinOutbound(item.now ?? '') && !picked);
                        return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          // Long press turns the filter into a bypass: the engine gets
                          // DIRECT, the chip goes grey, nobody has to hunt for DIRECT
                          // in the server list.
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            ref
                                .read(portalBypassProvider.notifier)
                                .toggle(ref, item);
                          },
                          child: Opacity(
                            opacity: bypassed ? 0.45 : 1,
                            child: ChoiceChip(
                          showCheckmark: false,
                          // Five layouts, one row each: name, name+server,
                          // icon+server, icon. Everything centres by construction.
                          label: Builder(
                            builder: (context) {
                              // 0 name · 1 name+server · 2 name+server+icon ·
                              // 3 icon+server · 4 icon
                              final showIcon = display >= 2;
                              final showName = display <= 2;
                              final showServer =
                                  display == 1 || display == 2 || display == 3;
                              final mark = SizedBox.square(
                                dimension: 16,
                                child: CommonTargetIcon(
                                  src: item.icon,
                                  fallback: GroupMonogram(item.name),
                                ),
                              );
                              // A bypassed filter has no server on screen at all:
                              // the user should see "nothing goes through here", not
                              // the word DIRECT.
                              // What the user just picked wins over what the engine
                              // has confirmed: the chip must name the chosen server
                              // in the same frame as the tap.
                              final server =
                                  bypassed ? null : (picked ? pendingByGroup[item.name] : item.now);
                              final text = [
                                if (showName) item.name,
                                if (showServer &&
                                    server != null &&
                                    server != item.name)
                                  server,
                              ].join(' · ');
                              if (!showIcon) {
                                return Text(text.isEmpty ? item.name : text);
                              }
                              if (text.isEmpty) return mark;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  mark,
                                  const SizedBox(width: 6),
                                  Text(text),
                                ],
                              );
                            },
                          ),
                          selected: item.name == active,
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            ref
                                .read(portalGroupProvider.notifier)
                                .pick(item.name);
                            // The porthole's mark reads the profile's current group; a
                            // chip that only moved its own state left the two disagreeing.
                            ref
                                .read(proxiesActionProvider.notifier)
                                .updateCurrentGroupName(item.name);
                          },
                            ),
                          ),
                        ),
                      );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 18,
          child: _canForward
              ? GlyphIcon(AppGlyphs.chevronForward, size: 14, color: hint)
              : null,
        ),
      ],
    );
  }
}

/// The legacy palette's three traffic lights: fast, tolerable, bad.
/// The live green of the portal controls. The neon version is right on the dark screen
/// and reads as "salad" on white, so light theme gets a deeper emerald instead.
Color _liveGreen(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF00F5A0)
        : const Color(0xFF0E9F6E);

// Theme-aware: the neon palette is right on the dark screen and unreadable on white.
Color _delayFast(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF00F5A0)
    : const Color(0xFF0E9F6E);
Color _delaySlow(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFC107)
    : const Color(0xFFB26A00);
Color _delayBad(BuildContext context) => Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFF4B6E)
    : const Color(0xFFB3261E);

Color _delayColor(BuildContext context, int? value) {
  if (value == null) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF7C8699)
        : const Color(0xFF5F6B7A);
  }
  if (value <= 0) return _delayBad(context); // timeout
  if (value <= 399) return _delayFast(context);
  if (value <= 1499) return _delaySlow(context);
  return _delayBad(context);
}

String sortLabelFor(BuildContext context, PortalSort sort) {
  final l10n = context.appLocalizations;
  return switch (sort) {
    PortalSort.subscription => l10n.sortAsSubscription,
    PortalSort.ping => l10n.sortByPing,
    PortalSort.alphabet => l10n.sortByName,
  };
}

String _delayText(int? value) {
  if (value == null) return '—';
  if (value <= 0) return '—';
  return '$value ms';
}

class _ServerRow extends ConsumerStatefulWidget {
  const _ServerRow({
    required this.group,
    required this.proxy,
    required this.selected,
    this.xrayServer,
    this.tcpHost = '',
    this.tcpPort = 0,
  });

  final Group group;
  final Proxy proxy;
  final bool selected;

  /// The child's own configuration for this row, when the list is the child's: a tap then
  /// restarts the child on this node instead of asking the engine to change a proxy.
  final XrayServerConfig? xrayServer;

  /// Where this server listens, when it is known: the row then times a TCP handshake
  /// instead of asking a core that either does not hold the server or cannot report it.
  final String tcpHost;
  final int tcpPort;

  @override
  ConsumerState<_ServerRow> createState() => _ServerRowState();
}

class _ServerRowState extends ConsumerState<_ServerRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.selected ? 1 : 0,
  );

  @override
  void didUpdateWidget(_ServerRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _controller.forward(from: 0);
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allGroups = ref.watch(groupsProvider);
    final byName = {for (final item in allGroups) item.name: item};
    String? resolve(String? name, [int depth = 0]) {
      if (name == null || depth > 6) return null;
      final next = byName[name];
      if (next == null) return name;
      return resolve(next.now, depth + 1);
    }

    final node = byName.containsKey(widget.proxy.name)
        ? resolve(widget.proxy.name)
        : null;
    final measurable = widget.tcpHost.isNotEmpty && widget.tcpPort > 0;
    final delay = measurable
        ? ref.watch(tcpDelayProvider)[widget.proxy.name]
        : ref.watch(delayProvider(proxyName: node ?? widget.proxy.name));
    final color = widget.selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        // The highlight arrives as a wave: a bright edge sweeps in from the left and
        // settles into the row's tint, so the eye can follow the switch.
        final sweep = widget.selected ? (1 - t) : 0.0;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: scheme.primaryContainer.withValues(alpha: 0.16 + 0.84 * t),
            gradient: sweep <= 0
                ? null
                : LinearGradient(
                    begin: Alignment(-1 + 2 * t, 0),
                    end: Alignment(0.4 + 2 * t, 0),
                    colors: [
                      scheme.primary.withValues(alpha: 0),
                      scheme.primary.withValues(alpha: 0.45 * sweep),
                      scheme.primary.withValues(alpha: 0),
                    ],
                  ),
          ),
          child: child,
        );
      },
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: GlyphIcon(
          widget.selected ? AppGlyphs.check : AppGlyphs.proxies,
          size: 20,
          color: color,
        ),
        title: Text(
          node == null || node == widget.proxy.name
              ? widget.proxy.name
              : '${widget.proxy.name} · $node',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: widget.selected ? scheme.onPrimaryContainer : null,
            fontWeight: widget.selected ? FontWeight.w600 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The protocol is part of the row, always: it is what distinguishes two
            // servers of the same country, and hiding it behind a gesture made the list
            // read as if every server spoke the same thing.
            Text(
              widget.proxy.type.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _delayText(delay),
              style: theme.textTheme.labelMedium?.copyWith(
                color: _delayColor(context, delay),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        onTap: () {
          HapticFeedback.selectionClick();
          final server = widget.xrayServer;
          if (server != null) {
            // The simple portal's list is the child's, and a tap there is the child's
            // business: keep the pick and restart the child on it. The engine is not asked
            // to change a proxy it does not have — it has none in this mode.
            unawaited(_startFromList(ref, server));
            return;
          }
          // Picking a portal by hand is also the way out of a bypass: the filter stops
          // being grey, because it is no longer routed around the portal.
          ref.read(portalBypassProvider.notifier).forget(widget.group.name);
          ref
              .read(portalPendingProvider.notifier)
              .pick(widget.group.name, widget.proxy.name);
          // The engine answers for itself, and this is what the list shows when it has
          // nothing to say — a fresh start, or a return from the simple portal.
          ref
              .read(portalSelectionProvider.notifier)
              .pickRule(widget.group.name, widget.proxy.name);
          ref.read(proxiesActionProvider.notifier).changeProxy(
                groupName: widget.group.name,
                proxyName: widget.proxy.name,
              );
        },
        // A long press answers the question a person actually has about one server: does
        // this one respond, and how fast — not what protocol it speaks, which is on the row
        // already.
        onLongPress: () {
          HapticFeedback.mediumImpact();
          if (measurable) {
            unawaited(
              ref.read(tcpDelayProvider.notifier).measureOne(
                    widget.proxy.name,
                    widget.tcpHost,
                    widget.tcpPort,
                  ),
            );
            return;
          }
          unawaited(
            _testDelayWithEngine(
              ref,
              [widget.proxy],
              wasRunning: ref.read(runTimeProvider) != null,
            ),
          );
        },
      ),
    );
  }
}

/// Plan status and the provider's announcement in one card.
class PortalPlanCard extends ConsumerWidget {
  const PortalPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(currentProfileProvider);
    final announcement = ref.watch(announcementProvider);
    // The panel's title is a sentence, not a name; the card shows the name.
    final name = profile == null
        ? ''
        : (profile.headers.displayName ??
            profile.headers.serviceName ??
            profile.realLabel);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // One line, as approved: name and mark first, then the two facts separated by
            // middle dots. Dashes stand in when the panel sends nothing, so the shape never
            // changes between accounts.
            if (profile != null)
              Builder(
                builder: (context) {
                  final facts = SubscriptionFacts.of(profile);
                  final meta = theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
                  final expiry = facts.expiry == '—'
                      ? '—'
                      : context.appLocalizations.expiresUntil(facts.expiry);
                  return Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$name ${facts.mark}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '  ·  ', style: meta),
                        TextSpan(text: facts.traffic, style: meta),
                        TextSpan(text: '  ·  ', style: meta),
                        TextSpan(text: expiry, style: meta),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              )
            else
              Text(
                name,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurface),
              ),
            if (announcement != null && announcement.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 8),
              Text(
                announcement,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reorder and hide the group filters. A sheet, not a page: it edits a row of chips.
Future<void> showPortalFilterEditor(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _FilterEditorSheet(),
  );
}

class _FilterEditorSheet extends ConsumerWidget {
  const _FilterEditorSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(portalFiltersProvider);
    final groups = portalGroups(ref.watch(groupsProvider));
    final order = filters.order.isEmpty
        ? [for (final group in groups) group.name]
        : [
            ...filters.order.where((name) => groups.any((g) => g.name == name)),
            ...groups
                .map((g) => g.name)
                .where((name) => !filters.order.contains(name)),
          ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.appLocalizations.filtersTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              context.appLocalizations.filtersHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                onReorder: (from, to) {
                  final next = [...order];
                  if (to > from) to -= 1;
                  next.insert(to, next.removeAt(from));
                  ref.read(portalFiltersProvider.notifier).reorder(next);
                },
                children: [
                  for (final (index, name) in order.indexed)
                    ListTile(
                      key: ValueKey(name),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The handle people already know how to drag.
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: GlyphIcon(AppGlyphs.dragHandle, size: 20),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 20,
                            child: CommonTargetIcon(
                              src: groups
                                      .where((g) => g.name == name)
                                      .firstOrNull
                                      ?.icon ??
                                  '',
                              fallback: GroupMonogram(name),
                            ),
                          ),
                        ],
                      ),
                      title: Text(name),
                      trailing: Switch(
                        value: !filters.hidden.contains(name),
                        onChanged: (_) => ref
                            .read(portalFiltersProvider.notifier)
                            .toggle(name),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Both corner badges stay hidden until a double tap asks for them: a permanent
/// counter is noise on a screen that is about the portal, not about the numbers.
class PortalBadgeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final portalProfilesBadgeProvider =
    NotifierProvider<PortalBadgeNotifier, bool>(PortalBadgeNotifier.new);
final portalConnectionsBadgeProvider =
    NotifierProvider<PortalBadgeNotifier, bool>(PortalBadgeNotifier.new);



/// A reason the portal could not move, carried as a sentence the owner can read.
class _PortalSwitchFailure implements Exception {
  const _PortalSwitchFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// How long the engine gets to take a new mode before the switch calls it a failure.
const _modeApplyTimeout = Duration(seconds: 12);

/// A switch already in flight. A second tap is dropped rather than queued: two transactions
/// over one portal can only end with the second undoing the first.
var _portalSwitching = false;

/// Moves the portal between the two modes as one transaction.
///
/// The steps are ordered, not parallel: close the portal, stop the previous core, start the
/// next one, wait for the engine to have taken the new mode, move the route, ignite the
/// portal again. Each step is something that answered, so a failure can be caught where it
/// happened; when one does, the previous mode and core come back and the reason is shown.
/// A switch that half happened would leave a portal carrying nothing with nothing on screen
/// to say why.
Future<void> _switchPortal(WidgetRef ref, {required bool toSimple}) async {
  if (_portalSwitching) return;
  _portalSwitching = true;
  final setup = ref.read(setupActionProvider.notifier);
  final previousMode = ref.read(patchClashConfigProvider.select((s) => s.mode));
  final wasRunning = ref.read(runTimeProvider) != null;
  try {
    // 1. The portal goes down first: the tun must not outlive the core that reads it.
    if (wasRunning && !await setup.setRunning(false)) {
      throw const _PortalSwitchFailure('the portal did not stop');
    }
    // 2. The child is stopped before the next core wants the tunnel, and the answer is the
    // plugin's: a stop that did not happen cannot be treated as one that did.
    final stopped = await XrayCore.instance.stop();
    if (!stopped.ok && !stopped.cancelled) {
      throw _PortalSwitchFailure('the portal core did not stop: ${stopped.reason}');
    }
    // 3-5. The next core, then the mode, then the route — in that order, and only as far
    // as each step answers.
    if (toSimple) {
      final entered = await _enterSimplePortal(ref);
      if (!entered.ok) {
        throw _PortalSwitchFailure(
          entered.cancelled
              ? 'the switch to the portal was cancelled'
              : entered.reason,
        );
      }
    } else {
      // The simple portal never pushed an engine config — that is exactly what "only Xray"
      // means — so the engine comes back with nothing applied: its groups read as empty and
      // the core answers "config is not applied". The profile has to be pushed before the
      // mode is asked for, or the network mode has no servers to show.
      final applied = await setup.applyProfile(force: true);
      if (!applied) {
        throw const _PortalSwitchFailure(
          'the portal network could not be applied: the profile was rejected',
        );
      }
      final mode = await setup.pickMode(Mode.rule);
      if (!mode.ok) {
        throw _PortalSwitchFailure(
          mode.cancelled ? 'the switch to the network was cancelled' : mode.reason,
        );
      }
    }
    if (wasRunning) {
      // In the simple portal there is no engine config to wait for: the mode is a setting
      // and the tunnel is the child's, so the start that follows is the whole answer. In
      // the network mode the engine still has to take the new config first.
      if (!toSimple) {
        final applied = await _awaitMode(ref, Mode.rule);
        if (!applied.ok) {
          throw _PortalSwitchFailure(applied.reason);
        }
      }
      // 6. Ignite: the same portal, on the other core. The start's own answer is the one
      // that matters, and its reason is what the owner is shown when it is not `ok`.
      if (!await setup.setRunning(true)) {
        final reason = setup.lastPortalFailure;
        throw _PortalSwitchFailure(
          reason.isEmpty ? 'the portal did not start again' : reason,
        );
      }
    }
  } catch (error) {
    await _rollBackPortal(
      ref,
      previousMode: previousMode,
      wasRunning: wasRunning,
    );
    _reportSwitchFailure(error);
  } finally {
    _portalSwitching = false;
  }
}

/// Waits until the engine runs what the settings now say.
///
/// A mode change is a config push; until the Core answers it the route is still the old
/// one, and traffic moved into it would go nowhere. The applied inputs are the only honest
/// answer the app has to "the engine has taken it".
///
/// A push that failed does not become true by waiting: the reason the Core gave is known
/// the moment it answered, and waiting the deadline out only replaces it with a timeout
/// that names nothing. The deadline stays as the last resort for a Core that is merely slow,
/// and even then the message says that, not "12 s" alone.
Future<PortalCoreResult> _awaitMode(WidgetRef ref, Mode mode) async {
  final setup = ref.read(setupActionProvider.notifier);
  final deadline = DateTime.now().add(_modeApplyTimeout);
  // An error left over from an earlier push is not this push's; only a new one is.
  final before = setup.lastConfigError;
  while (DateTime.now().isBefore(deadline)) {
    if (ref.read(patchClashConfigProvider).mode == mode &&
        await setup.inputsApplied()) {
      return const PortalCoreResult.ok();
    }
    final failure = setup.lastConfigError;
    if (failure.isNotEmpty && failure != before) {
      return PortalCoreResult.nativeError(failure);
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return PortalCoreResult.nativeError(
    'the engine did not take ${mode.name} within ${_modeApplyTimeout.inSeconds} s',
  );
}

/// Puts the previous mode and the previous core back, best effort.
///
/// The rollback reads the same typed answers as the switch: a stop, a mode and a start are
/// only done when the core said so. Its own failure is logged rather than thrown — it must
/// not replace the reason the switch failed, which is what the owner needs to see.
Future<void> _rollBackPortal(
  WidgetRef ref, {
  required Mode previousMode,
  required bool wasRunning,
}) async {
  final setup = ref.read(setupActionProvider.notifier);
  try {
    final stopped = await XrayCore.instance.stop();
    if (!stopped.ok && !stopped.cancelled) {
      throw _PortalSwitchFailure('the portal core did not stop: ${stopped.reason}');
    }
    if (previousMode == Mode.global) {
      // The tunnel again, with the child on the node the profile still names.
      final entered = await _enterSimplePortal(ref);
      if (!entered.ok) {
        throw _PortalSwitchFailure('the portal mode did not come back: ${entered.reason}');
      }
    } else {
      final mode = await setup.pickMode(previousMode);
      if (!mode.ok) {
        throw _PortalSwitchFailure(
          'the network mode did not come back: ${mode.reason}',
        );
      }
    }
    if (wasRunning && !await setup.setRunning(true)) {
      throw const _PortalSwitchFailure('the portal did not start again');
    }
  } catch (error) {
    commonPrint.log(
      'portal switch rollback failed: ${compactError(error)}',
      logLevel: LogLevel.error,
    );
  }
}

/// The failure as a sentence, in the app's own log and on the screen.
void _reportSwitchFailure(Object error) {
  final reason = error is _PortalSwitchFailure
      ? error.reason
      : compactError(error);
  commonPrint.log('portal switch failed: $reason', logLevel: LogLevel.error);
  dialogs.showNotifier(
    currentAppLocalizations.portalSwitchFailed(reason),
    level: MessageLevel.error,
  );
}
