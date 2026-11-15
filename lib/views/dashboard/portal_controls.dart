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
import 'package:fl_clash/core/xray_config.dart';
import 'package:fl_clash/core/proxy_endpoints.dart';
import 'package:fl_clash/core/xray_ping.dart';
import 'package:fl_clash/core/subscription_availability.dart';
import 'package:fl_clash/core/xray_subscription.dart';
import '../profiles/subscription_facts.dart';
import 'package:fl_clash/core/xray_switch.dart';
import 'package:fl_clash/plugins/xray.dart';
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
  @override
  Map<String, int?> build() => const {};

  Future<void> measureAll(List<(String, String, int)> targets) async {
    if (targets.isEmpty) return;
    state = {...state, for (final t in targets) t.$1: null};
    for (final (name, host, port) in targets) {
      final value = await tcpPing(host, port);
      state = {...state, name: value};
    }
  }

  Future<void> measureOne(String name, String host, int port) async {
    state = {...state, name: null};
    final value = await tcpPing(host, port);
    state = {...state, name: value};
  }
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


/// What is actually crossing the wire right now, taken from the engine's own connection
/// list: how many connections are open, how fast they move, and how much belongs to each
/// filter. Nothing here is inferred or animated for show.
typedef PortalLive = ({
  int connections,
  int down,
  int up,
});

final portalLiveProvider = Provider<PortalLive>((ref) {
  final list = ref.watch(requestsProvider).list;
  var down = 0;
  var up = 0;
  for (final request in list) {
    final requestDown = request.downloadSpeed ?? 0;
    final requestUp = request.uploadSpeed ?? 0;
    down += requestDown;
    up += requestUp;
  }
  return (
    connections: list.length,
    down: down,
    up: up,
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
  visible.sort((a, b) {
    final ia = order.indexOf(a.name);
    final ib = order.indexOf(b.name);
    if (ia == -1 && ib == -1) return 0;
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return visible;
}

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
  final servers = parseXraySubscription(body);
  if (servers.isNotEmpty) {
    commonPrint.log(
      'xray subscription: ${servers.length} servers, '
      'first=${servers.take(3).map((s) => s.label).join(' | ')}',
    );
  }
  return servers;
});

/// Whether the current subscription carries the engine's own format.
///
/// The "Сеть порталов" switch is meaningless without it: rules live in that YAML, and a
/// subscription the panel only serves for Xray has nothing to route. Unknown counts as
/// available so the switch does not flicker off while the file is being checked.
final engineFormatAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return false;
  try {
    final file = await profile.file;
    return await file.exists() && await file.length() > 32;
  } catch (_) {
    return false;
  }
});

/// Hands the traffic to Xray for the simple portal.
///
/// Order matters: the child must answer before the engine is told to send everything to it,
/// otherwise the switch would show a portal that cannot carry a packet. If the pick cannot
/// be resolved — a builtin, or a name the applied config no longer has — the mode is left
/// alone rather than pointing at a dead port.
Future<void> _enterSimplePortal(WidgetRef ref) async {
  // The strip keeps a null group name until the owner picks one; the first group is what
  // the list is showing in that case, so the pick lives there.
  final groupName = ref.read(portalGroupProvider) ??
      ref.read(groupsProvider).firstOrNull?.name;
  final chosen =
      groupName == null ? null : ref.read(selectedProxyNameProvider(groupName));
  // The second core prefers its own node list: the panel served it for exactly this
  // purpose, and its names need not exist in the engine's config at all. The engine's
  // config is the fallback, so a subscription with only YAML still works.
  Map<String, dynamic>? node;
  final profile = ref.read(currentProfileProvider);
  if (profile != null) {
    final body = await profile.readXrayFormat();
    if (body != null) {
      final servers = parseXraySubscription(body);
      final server = xrayServerFor(servers, chosen);
      if (server != null) {
        // Each server is its own full configuration; the chosen one is what the core runs.
        // Only the socks entry point is ours to set.
        final started = await XrayCore.instance.start(
          withSocksInbound(jsonEncode(server.config)),
        );
        if (started['ok'] != true) return;
        await ref.read(setupActionProvider.notifier).pickMode(Mode.global);
        await ref
            .read(proxiesActionProvider.notifier)
            .changeProxy(groupName: 'GLOBAL', proxyName: 'XRAY-SOCKS');
        return;
      }
      node = xrayNodeFor(parseShareLinks(body), chosen);
    }
  }
  if (node == null && chosen != null) {
    final path = await appPath.configFilePath;
    node = await nodeDefinitionFor(path, chosen);
  }
  if (node == null) {
    // No node for the child means the portal would be a dead port, so the mode stays put.
    return;
  }
  final started = await XrayCore.instance.start(xrayConfigJson(node));
  if (started['ok'] != true) return;
  await ref.read(setupActionProvider.notifier).pickMode(Mode.global);
  await ref
      .read(proxiesActionProvider.notifier)
      .changeProxy(groupName: 'GLOBAL', proxyName: 'XRAY-SOCKS');
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
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull;
    final sort = ref.watch(portalSortProvider);
    final engineAvailable =
        ref.watch(engineFormatAvailableProvider).value ?? true;
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
              Switch(
                value: mode == Mode.rule && engineAvailable,
                activeThumbColor: _liveGreen(context),
                activeTrackColor: _liveGreen(context).withValues(alpha: 0.4),
                // No engine format, no rules: the control stays visible but dead, so the
                // owner sees why instead of a switch that does nothing.
                onChanged: !engineAvailable
                    ? null
                    : (value) {
                  HapticFeedback.selectionClick();
                  if (value) {
                    // Back to the portal network: leave the child before the engine starts
                    // routing again, so nothing is left holding the port.
                    ref.read(setupActionProvider.notifier).pickMode(Mode.rule);
                    XrayCore.instance.stop();
                    return;
                  }
                  // The animation has already begun from this tap; the child, the hand-over
                  // and the mode change settle behind it.
                        unawaited(_enterSimplePortal(ref));
                      },
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
    final group = groups.where((g) => g.name == groupName).firstOrNull ??
        groups.firstOrNull;
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
    // The simple portal is driven by the second core, whose build of the same subscription
    // names its own servers. Showing the engine's list here would offer nodes the running
    // core does not have — and hide the extras it does.
    final xrayServers = simple
        ? (ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[])
        : const <XrayServerConfig>[];
    // One source for "what is chosen": the profile's own selection, which changeProxy
    // writes optimistically. No per-filter special cases — if a server was picked, it is
    // picked, whether the group is RF services, Chinese services or YouTube. When the
    // group routes to a built-in, its name is not in the member list, so nothing lights
    // up without needing a second rule.
    final bypassedGroup = ref.watch(portalBypassProvider).containsKey(group.name);
    final chosenName = ref.watch(selectedProxyNameProvider(group.name));
    final selectedName = bypassedGroup
        ? null
        : (pending ?? (xrayServers.isNotEmpty ? null : chosenName));
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
    if (targets.isNotEmpty &&
        !ref.watch(tcpDelayProvider.select((m) => m.isNotEmpty))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        unawaited(ref.read(tcpDelayProvider.notifier).measureAll(targets));
      });
    }
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
        final xrayDelays = ref.watch(tcpDelayProvider);
        int rank(Proxy p) {
          final value = xrayServerByName.containsKey(p.name)
              ? xrayDelays[p.name]
              : ref.watch(delayProvider(proxyName: p.name));
          // -1 is mihomo's timeout marker, not a fast server.
          return value == null || value <= 0 ? 1 << 30 : value;
        }
        members.sort((a, b) => rank(a).compareTo(rank(b)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    this.tcpHost = '',
    this.tcpPort = 0,
  });

  final Group group;
  final Proxy proxy;
  final bool selected;

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
          // Picking a portal by hand is also the way out of a bypass: the filter stops
          // being grey, because it is no longer routed around the portal.
          ref.read(portalBypassProvider.notifier).forget(widget.group.name);
          ref
              .read(portalPendingProvider.notifier)
              .pick(widget.group.name, widget.proxy.name);
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

