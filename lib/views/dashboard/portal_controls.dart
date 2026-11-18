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
import 'package:fl_clash/core/sweep_ledger.dart';
import 'package:fl_clash/core/xray_measure.dart';
import 'package:fl_clash/core/xray_subscription.dart';
import 'package:fl_clash/core/portal_document.dart';
import 'package:fl_clash/core/portal_feed.dart';
import 'package:fl_clash/l10n/l10n.dart';
import '../profiles/subscription_facts.dart';
import 'package:fl_clash/plugins/portal_runtime.dart';
import 'package:fl_clash/plugins/portal_switch_timing.dart';
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

/// Delays measured by this process, for the servers of the simple portal.
///
/// The engine only reports delays for the servers it holds; the child's servers are not among
/// them, so a TCP handshake from here is the only measurement those rows can have. An engine
/// row is never put in this map: its number is the engine's own, taken through the tunnel it
/// built. A missing key means "not asked yet"; a null entry means "asked, no answer" — and a
/// null is also the honest answer for a name that only resolves to the tunnel's own address.
final tcpDelayProvider =
    NotifierProvider<TcpDelayNotifier, Map<String, int?>>(TcpDelayNotifier.new);

/// The engine's rows' numbers, kept apart from the child's.
///
/// The two lists name different servers and measure them differently: the child's number is a
/// request this process dials through its node, the engine's is the engine's own URLTEST. They
/// look the same on screen and must never share storage: a name that exists in both
/// subscriptions would otherwise show the other core's number, and a switch would look like
/// nothing had been measured at all.
final engineDelayProvider =
    NotifierProvider<EngineDelayNotifier, Map<String, int?>>(EngineDelayNotifier.new);

/// Whether the list pings itself on a timer, and the timer itself.
///
/// A long press on the bolt turns it on and off; while it is on the whole list is measured
/// every [_autoPingInterval], which is what makes "auto" of a panel's own selector mean
/// something. It starts off in every session: a timer that survives a restart is a timer the
/// owner has forgotten about.


class EngineDelayNotifier extends Notifier<Map<String, int?>> {
  final SweepLedger ledger = SweepLedger();

  int get sweepId => ledger.id;
  Mode? get sweepMode => ledger.mode;
  int beginSweep(Mode mode) => ledger.begin(mode);
  void cancelSweep() {
    ledger.cancel();
  }

  bool isCurrentSweep(int id, Mode mode) => ledger.isCurrent(id, mode);
  bool isFresh(String name) => ledger.isFresh(name);

  @override
  Map<String, int?> build() => const {};

  void record(String name, int? ms) {
    state = {...state, name: ms};
    ledger.record(name, ms);
  }

  void resetForProfile() {
    ledger.reset();
    state = const {};
  }
}

class TcpDelayNotifier extends Notifier<Map<String, int?>> {
  /// The sweep's bookkeeping: freshness of each row and which sweep is the newest.
  ///
  /// Kept in a pure object so the rules that were wrong twice (a cancelled sweep coming back
  /// to life, another profile's dates looking fresh) are pinned by tests instead of memory.
  final SweepLedger ledger = SweepLedger();

  /// When each row was measured, by the phone's own clock.
  Map<String, DateTime> get measuredAt => ledger.measuredAt;

  /// The newest sweep's number. It only ever grows.
  int get sweepId => ledger.id;

  /// The mode the newest sweep belongs to.
  Mode? get sweepMode => ledger.mode;

  /// Starts a sweep for [mode] and answers its number.
  int beginSweep(Mode mode) => ledger.begin(mode);

  /// Supersedes whatever is running — a mode switch, a new list.
  void cancelSweep() {
    ledger.cancel();
    _generation++;
  }

  /// True while [id] is still the newest sweep and the mode has not changed.
  bool isCurrentSweep(int id, Mode mode) => ledger.isCurrent(id, mode);

  /// True when [name] has a number younger than the freshness window.
  bool isFresh(String name) => ledger.isFresh(name);
  /// Bumped by every sweep, and by a profile change. An answer arriving under an older
  /// number belongs to servers the list no longer shows — usually names that repeat in the
  /// new subscription — so it is dropped instead of written under the current key.
  int _generation = 0;

  @override
  Map<String, int?> build() {
    // The measurements belong to the profile: a different one is a different set of servers,
    // so the rows, their dates and the sweep in flight all go with it instead of lighting up
    // names that only look alike.
    ref.watch(currentProfileIdProvider);
    ref.onDispose(() => _generation++);
    return const {};
  }

  /// Forgets everything measured for the previous profile: its rows, their dates and the
  /// sweep that was running. A profile change is a different subscription, and a number from
  /// the old one must not look fresh under a name that only matches by accident.
  void resetForProfile() {
    ledger.reset();
    state = const {};
    _generation++;
  }

  /// The node the child is carrying traffic on, or null when no child holds the tunnel.
  ///
  /// One answer, written from a sweep that measured the row itself.
  void record(String name, int? ms) {
    state = {...state, name: ms};
    // A dash counts as a measurement too: asking again inside the window would only spend
    // another timeout on a node that just refused.
    ledger.record(name, ms);
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
const portalSimpleGroupName = portalRowsGroupName;

/// Both feeds' counts, as a provider, so a control redraws the moment one moves.
///
/// The ledger itself is a plain [PortalFeeds] on purpose: the fetch path (a model, no widget,
/// no container) has to be able to count an attempt, and a failed download must be counted
/// whether or not the dashboard is open.
class PortalFeedsNotifier extends Notifier<Map<PortalFeed, FeedStrikes>> {
  @override
  Map<PortalFeed, FeedStrikes> build() {
    void onChange() => state = portalFeeds.snapshot;
    portalFeeds.addListener(onChange);
    ref.onDispose(() => portalFeeds.removeListener(onChange));
    return portalFeeds.snapshot;
  }
}

final portalFeedsProvider =
    NotifierProvider<PortalFeedsNotifier, Map<PortalFeed, FeedStrikes>>(
        PortalFeedsNotifier.new);

/// One mode's answer, as the controls read it.
typedef ModeAvailability = ({
  bool available,
  FeedStrikes strikes,
  String reason,
});

/// Whether each mode can be entered, and why not.
///
/// Two facts per mode, and the stricter one wins: the app's own count of failed attempts at
/// this subscription ([portalFeeds]), and the document already on disk, which is all a fresh
/// start has before any fetch. The count is what makes a panel answering `502` visible at
/// all: the file it left behind is still a working config, so the file alone would keep
/// offering a mode whose every new fetch fails. Unknown — still loading — counts as
/// available, so a control never flickers off while the answer is on its way.
final portalAvailabilityProvider =
    Provider<({ModeAvailability engine, ModeAvailability xray})>((ref) {
  final strikes = ref.watch(portalFeedsProvider);
  final engineFile = ref.watch(engineFormatStatusProvider).value;
  final servers = ref.watch(xrayServersProvider).value;
  final engineStrikes = strikes[PortalFeed.engine] ?? const FeedStrikes();
  final xrayStrikes = strikes[PortalFeed.xray] ?? const FeedStrikes();
  final fileProblem = engineFile == null || engineFile.status == EngineFormatStatus.ok
      ? ''
      : engineFile.reason;
  // No nodes is not a slow answer: the simple portal has nothing to start with, and the
  // switch has to say so rather than open a portal that carries no traffic.
  final noServers = servers != null && servers.isEmpty;
  return (
    engine: (
      available: !engineStrikes.blocked && fileProblem.isEmpty,
      strikes: engineStrikes,
      reason: engineStrikes.blocked ? engineStrikes.reason : fileProblem,
    ),
    xray: (
      available: !xrayStrikes.blocked && !noServers,
      strikes: xrayStrikes,
      reason: xrayStrikes.blocked
          ? xrayStrikes.reason
          : (noServers ? 'this subscription carries no nodes for the portal' : ''),
    ),
  );
});

/// A refusal's reason, with the count in the reader's own language.
///
/// The count is the fact the owner can act on ("it failed three times"), and the detail is
/// the last failure's own words (`http 502`), which is what a support question needs.
String _availabilityReason(AppLocalizations l10n, ModeAvailability availability) {
  final strikes = availability.strikes;
  if (!strikes.blocked) return availability.reason;
  return '${l10n.portalStrikes(strikes.failures)} (${strikes.reason})';
}

/// The rows this mode draws, from the owner that answers or from the mode's own source.
///
/// The two modes read one subscription in two formats, and each mode reads only its own:
///
/// * the simple portal's `live` answer is the child's servers, and only while the child holds
///   the tunnel; its fallback is the same servers read from the profile, named `servers`;
/// * the network mode's `live` answer is the engine's groups, and only while the engine holds
///   the tunnel; with the portal closed it falls back to the engine's last own answer for this
///   profile and then the profile's engine-format `proxies:`.
///
/// A group held from the other mode is dropped before it is drawn, and a `live` group whose
/// owner is not this mode's is not an answer.
PortalShown _portalShown(
  WidgetRef ref, {
  required bool simple,
  required List<Group> groups,
  required String? groupName,
  OwnedGroup? heldEngine,
  OwnedGroup? heldChild,
  void Function(OwnedGroup)? remember,
}) {
  final status = ref.watch(portalStatusProvider);
  final profileKey = '${ref.watch(currentProfileIdProvider) ?? ''}';
  final mode = simple ? RowsOwner.child : RowsOwner.engine;
  final servers = simple
      ? (ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[])
      : const <XrayServerConfig>[];
  final cachedRows = simple
      ? const <PortalRow>[]
      : (ref.watch(portalEngineRowsProvider)[profileKey] ??
          const <PortalRow>[]);
  final profileRows = simple
      ? const <PortalRow>[]
      : (ref.watch(profilePortalRowsProvider).value ?? const <PortalRow>[]);
  // Each mode reads its own cache and no other: the child's remembered servers for the simple
  // portal, the engine's remembered groups for the network mode.
  final childCacheRows = simple
      ? (ref.watch(portalChildRowsProvider)[profileKey] ?? const <PortalRow>[])
      : const <PortalRow>[];
  // Whose rows are on offer: only a core that is reading the tunnel now answers for itself.
  final engineLive = !simple &&
      status.active &&
      status.owner == PortalOwner.mihomo
      ? groups.where((g) => g.name == groupName).firstOrNull ?? groups.firstOrNull
      : null;
  final childLive = simple &&
      status.active &&
      status.owner == PortalOwner.xray &&
      servers.isNotEmpty
      ? portalGroupOfServers(servers)
      : null;
  final live = engineLive != null
      ? (group: engineLive, owner: RowsOwner.engine)
      : childLive != null
          ? (group: childLive, owner: RowsOwner.child)
          : null;
  final shown = portalShownRows(
    mode: mode,
    live: live,
    held: simple ? heldChild : heldEngine,
    fallbacks: simple
        ? [
            (
              'childcache',
              portalGroupOfRows(childCacheRows).all.isEmpty
                  ? null
                  : portalGroupOfRows(childCacheRows),
            ),
            (
              'servers',
              portalFallbackGroup(
                simple: true,
                servers: servers,
                engineRows: const [],
              ),
            ),
          ]
        : [
            // The subscription is the answer until the engine itself speaks: a closed
            // portal has no groups, and the cached rows may belong to the other core or to
            // an older profile. Only when the document has nothing to show does the last
            // engine answer stand in — never before it.
            (
              'profile',
              portalFallbackGroup(
                simple: false,
                servers: const [],
                engineRows: profileRows,
              ),
            ),
            (
              'cache',
              portalFallbackGroup(
                simple: false,
                servers: const [],
                engineRows: cachedRows,
              ),
            ),
          ],
    remember: remember,
  );
  // What the owner actually sees, and where it came from: two cores, two caches, and the log
  // must name which one answered. Throttled to changes, so a rebuild storm stays readable.
  final items = shown.group?.all ?? const <Proxy>[];
  final mark = '${mode.name}|${shown.source}|${items.length}';
  if (mark != _portalListMark) {
    _portalListMark = mark;
    final names = items.take(10).map((item) => '${item.name}').join(' | ');
    commonPrint.log(
      'portal list: mode=${simple ? 'global' : 'rule'} owner=${status.owner?.name} '
      'source=${shown.source} rows=${items.length} names=$names',
    );
  }
  return shown;
}

String _portalListMark = '';

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
class PortalModeSwitch extends ConsumerStatefulWidget {
  const PortalModeSwitch({super.key});

  @override
  ConsumerState<PortalModeSwitch> createState() => _PortalModeSwitchState();
}

class _PortalModeSwitchState extends ConsumerState<PortalModeSwitch> {
  /// The last engine group this control drew, kept across a switch.
  ///
  /// A state field, not a provider: the list is rebuilt many times a frame and the memory has
  /// to outlive the rebuild without writing a provider during it. It is per owner — the
  /// engine's last group is not a row of the simple portal, and the child's is not a row of
  /// the network mode.
  OwnedGroup? _heldEngine;

  OwnedGroup? _heldChild;

  @override
  Widget build(BuildContext context) {
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
    // The owner that answers now wins; until it does, this mode's own rows do.
    final shown = _portalShown(
      ref,
      simple: simple,
      groups: groups,
      groupName: groupName,
      heldEngine: _heldEngine,
      heldChild: _heldChild,
      remember: (value) {
        if (value.owner == RowsOwner.engine) {
          _heldEngine = value;
        } else {
          _heldChild = value;
        }
      },
    );
    final group = shown.group;
    final sort = ref.watch(portalSortProvider);
    final autoPing = ref.watch(autoPingProvider);
    // Both modes answer through one provider: what is on disk, and how many times in a row
    // this run has failed to fetch it. Each control speaks only for its own mode, and the
    // stricter answer wins.
    final availability = ref.watch(portalAvailabilityProvider);
    final engineAvailable = availability.engine.available;
    final xrayAvailable = availability.xray.available;
    final engineReason = engineAvailable
        ? ''
        : context.appLocalizations
            .engineFormatUnusable(_availabilityReason(context.appLocalizations, availability.engine));
    final xrayReason = xrayAvailable
        ? ''
        : context.appLocalizations
            .portalModeUnavailable(_availabilityReason(context.appLocalizations, availability.xray));
    // Both dark is its own sentence: it names both reasons once, instead of leaving the
    // owner to work out why neither side of the switch moves.
    final bothUnavailable = !engineAvailable && !xrayAvailable;
    final shownReason = bothUnavailable
        ? context.appLocalizations.portalModesUnavailable(
            [availability.engine.reason, availability.xray.reason]
                .where((reason) => reason.isNotEmpty)
                .join(' · '),
          )
        : (simple ? engineReason : xrayReason);
    final testing = group != null &&
        ref.watch(
          delayTestingGroupsProvider.select((s) => s.contains(group.name)),
        );
    if (modes.length < 2) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                    message: bothUnavailable
                        ? shownReason
                        : (simple ? engineReason : xrayReason),
                    child: Switch(
                      // The thumb tells the truth about the mode the app is in, even when that
                      // mode has just gone dark: a portal that keeps working on its last good
                      // config must not look switched off.
                      value: mode == Mode.rule,
                      activeThumbColor: _liveGreen(context),
                      activeTrackColor: _liveGreen(context).withValues(alpha: 0.4),
                      // Dead only when neither side can be entered. With one side alive the
                      // switch stays live and the direction that is not offered refuses with its
                      // own reason, because a control that moves and snaps back teaches nothing.
                      onChanged: bothUnavailable
                          ? null
                          : (value) {
                              if (value ? !engineAvailable : !xrayAvailable) {
                                HapticFeedback.vibrate();
                                dialogs.showNotifier(
                                  value ? engineReason : xrayReason,
                                  level: MessageLevel.warning,
                                );
                                return;
                              }
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
            Builder(
              builder: (context) {
                // The same work serves a tap and the timer: measure the whole list in front of
                // the owner, whichever core it belongs to.
                void measureAll({required bool force}) {
                  final simple =
                      ref.read(patchClashConfigProvider).mode == Mode.global;
                  if (simple) {
                    final servers = <XrayServerConfig>[
                      for (final server
                          in ref.read(xrayServersProvider).value ??
                              const <XrayServerConfig>[])
                        if (server.port > 0) server,
                    ];
                    if (servers.isEmpty) return;
                    unawaited(
                      _testDelayWithChild(
                        ref,
                        servers,
                        wasRunning: running,
                        force: force,
                      ),
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
                      force: force,
                    ),
                  );
                }

                // The timer runs the same sweep without forcing: what it re-measures is what
                // has gone stale, which inside one period is the whole list anyway.
                ref.listen(autoPingProvider.select((s) => s.enabled), (previous, next) {
                  if (next) {
                    measureAll(force: false);
                  }
                });

                return GestureDetector(
                  // A long press sets the period, in this mode only: the number of requests a
                  // minute is a decision about the phone's battery, so it is the owner's to make.
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    _showAutoPingPeriod(context, ref);
                  },
                  child: IconButton(
              tooltip: context.appLocalizations.delayTest,
              // A delay test says which servers answer, so it must not depend on the portal
              // being open: the test wakes the engine for its duration and closes it again.
              // A tap is the switch: on, the list keeps refreshing itself; off, the numbers
              // grow stale and nothing is spent in the background.
              onPressed: () {
                HapticFeedback.mediumImpact();
                final auto = ref.read(autoPingProvider.notifier);
                final turningOn = !auto.current.enabled;
                auto.setEnabled(
                  turningOn,
                  tick: () => measureAll(force: false),
                );
                // A document built while the switch was off carries no schedule at all, so a
                // running core has to be restarted on one that does.
                final live = ref.read(portalStatusProvider);
                if (turningOn &&
                    live.active &&
                    live.owner == PortalOwner.xray) {
                  unawaited(
                    ref.read(setupActionProvider.notifier).reapplyPortalDocument(),
                  );
                }
              },
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
                      // The switch reads at a glance: lit while the list keeps measuring
                      // itself, faded when it does not.
                      color: autoPing.enabled
                          ? const Color(0xFF00F5A0)
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        // One line, not a tooltip: a phone has to say why a control does not move without
        // being long-pressed first. Two lines at most, so a long reason cannot push the list
        // off the dashboard.
        if (shownReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(
              shownReason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// The working screen's server list: a group strip with arrows (network mode only),
/// a tinted row for the chosen server, name left and delay right.
class PortalServerList extends ConsumerStatefulWidget {
  const PortalServerList({super.key});

  @override
  ConsumerState<PortalServerList> createState() => _PortalServerListState();
}

class _PortalServerListState extends ConsumerState<PortalServerList> {
  /// The last group this list drew, per owner, and the mode it was drawn in. A switch empties
  /// both sources for a moment — the engine has no groups until it takes the profile, the child
  /// has no servers until its subscription is read — and an empty list there is what the owner
  /// saw as a flicker. The owner is part of the memory: the engine's last group is not a row of
  /// the simple portal, and the child's is not a row of the network mode.
  OwnedGroup? _heldEngine;

  OwnedGroup? _heldChild;

  @override
  Widget build(BuildContext context) {
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
    // The engine's own answer is kept while it is still in hand: with the portal closed there
    // are no groups to ask, and 'Сеть порталов' must then draw the engine's names instead of
    // the portal's. The listen is not a write during the build — it fires when the engine
    // publishes, which is when there is something worth keeping.
    // Any switch of mode stops the sweep that belonged to the other list: the numbers it was
    // about to write are the servers of a list nobody is looking at any more.
    ref.listen(patchClashConfigProvider.select((s) => s.mode), (previous, next) {
      if (previous == next) return;
      // A bump, not a reset: the sweep that was running must not take the next number and
      // believe it is current again.
      ref.read(tcpDelayProvider.notifier).cancelSweep();
      ref.read(engineDelayProvider.notifier).cancelSweep();
      commonPrint.log('portal test: sweep cancelled, mode is now ${next.name}');
    });
    ref.listen(currentProfileIdProvider, (previous, next) {
      if (previous == next) return;
      // Another subscription: its rows, their dates and the sweep in flight are not this
      // profile's answers.
      ref.read(tcpDelayProvider.notifier).resetForProfile();
      ref.read(engineDelayProvider.notifier).resetForProfile();
    });
    ref.listen(xrayServersProvider, (previous, next) {
      final servers = next.value;
      if (servers == null || servers.isEmpty) return;
      ref.read(portalChildRowsProvider.notifier).remember(
            profileId: '${ref.read(currentProfileIdProvider) ?? ''}',
            servers: servers,
          );
      // Nothing to start here: `_TcpDelaySweep` owns the launch measurement, from a lifecycle
      // method, and the button asks for a fresh one.
    });
    ref.listen(groupsProvider, (previous, next) {
      if (next.isEmpty) return;
      final group =
          next.where((g) => g.name == groupName).firstOrNull ?? next.first;
      ref
          .read(portalEngineRowsProvider.notifier)
          .remember(
            profileId: '${ref.read(currentProfileIdProvider) ?? ''}',
            group: group,
          );
    });
    // The simple portal is driven by the child, whose build of the same subscription names
    // its own servers; the network mode draws the engine's. Each mode's rows come from its
    // own source, and from no other.
    final xrayServers = simple
        ? (ref.watch(xrayServersProvider).value ?? const <XrayServerConfig>[])
        : const <XrayServerConfig>[];
    final shown = _portalShown(
      ref,
      simple: simple,
      groups: groups,
      groupName: groupName,
      heldEngine: _heldEngine,
      heldChild: _heldChild,
      remember: (value) {
        if (value.owner == RowsOwner.engine) {
          _heldEngine = value;
        } else {
          _heldChild = value;
        }
      },
    );
    final group = shown.group;
    if (group != null && group.all.isNotEmpty) {
      // The tap → rows on screen, for the transitions file. The clock writes one line per tap
      // and answers nothing afterwards, so a list rebuilt every frame costs one comparison.
      portalSwitchClock.listPopulated(
        source: shown.source,
        rows: group.all.length,
        mode: simple ? 'global' : 'rule',
        owner: shown.owner.label,
        names: group.all.map((proxy) => proxy.name),
      );
    }
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
    // While the child's own list has not arrived, the rows on screen are still the ones its
    // stored pick names — so the highlight stays on the node that was confirmed, and it
    // moves only when a new pick has been acknowledged.
    final heldXrayPick =
        simple && xrayPick.isNotEmpty && group.all.any((p) => p.name == xrayPick);
    final selectedName = bypassedGroup
        ? null
        : xrayServers.isNotEmpty
            ? xrayPicked
            : heldXrayPick
                ? xrayPick
                : (pending ?? chosenName ?? rulesPick);
    // Measure once when the list arrives: a portal whose servers all read "—" until you
    // press something looks broken, and a closed portal is no reason not to know. Only the
    // simple portal is measured here: those are the servers no engine holds. In the network
    // mode the delay is the engine's own, taken through the tunnel it built — a TCP handshake
    // from this process to an engine node's name resolves through the running engine to its
    // fake-IP, and timing that measures the phone's own listener, not the node.
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
        final engineDelays = ref.watch(engineDelayProvider);
        final ranks = <String, int>{};
        for (final proxy in members) {
          final value = xrayServerByName.containsKey(proxy.name)
              ? xrayDelays[proxy.name]
              : engineDelays[proxy.name] ??
                  ref.read(delayProvider(proxyName: proxy.name));
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
        _TcpDelaySweep(
          servers: xrayServers,
          engineProxies: simple ? const <Proxy>[] : members,
          simple: simple,
          wasRunning: portalRuntime.status.value.active &&
              portalRuntime.status.value.owner ==
                  (simple ? PortalOwner.xray : PortalOwner.mihomo),
        ),
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
            // A row is timed by this process only when it is the child's server. The engine's
            // rows carry its own delay, which is a proxied measurement; a handshake to an
            // engine node's name from here would resolve to the engine's fake-IP.
            tcpHost: xrayServerByName[proxy.name]?.address ?? '',
            tcpPort: xrayServerByName[proxy.name]?.port ?? 0,
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
Future<PortalRuntimeAnswer> _restartChildOn(
  WidgetRef ref,
  XrayServerConfig server,
) async {
  // The tap is one entry of the same transaction the mode switch takes: the coordinator
  // keeps the tunnel, replaces the core that reads it, and moves the generation so an
  // acknowledgement from the core it just replaced cannot be mistaken for this one's.
  //
  // The document is the whole list with this node selected, never this node alone: the core
  // must keep timing the others for the list to have numbers at all.
  final servers = [
    for (final item in ref.read(xrayServersProvider).value ??
        const <XrayServerConfig>[])
      if (item.port > 0) item,
  ];
  final document = servers.any((item) => item.name == server.name)
      ? portalChildDocument(
          servers,
          selected: server.name,
          probeInterval: ref.read(autoPingProvider).enabled
              ? ref.read(autoPingProvider).interval
              : null,
        )
      : jsonEncode(server.config);
  final started = await portalRuntime.startChild(document);
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
  final started = await _restartChildOn(ref, server);
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
  final restored = await _restartChildOn(ref, server);
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

/// Starts one delay sweep for the servers the list is showing — whichever core they belong to.
///
/// From a lifecycle method, not the build pass: a widget can be rebuilt many times a frame for
/// reasons that have nothing to do with the servers, and starting the measurement there
/// restarted it on every rebuild while the map was still empty. The sweep owns its
/// cancellation — a newer list, or a mode switch, drops the answers of the older one.
class _TcpDelaySweep extends ConsumerStatefulWidget {
  const _TcpDelaySweep({
    required this.servers,
    required this.engineProxies,
    required this.simple,
    required this.wasRunning,
  });

  /// The second core's servers, empty in the network mode.
  final List<XrayServerConfig> servers;

  /// The engine's nodes, empty in the simple portal.
  final List<Proxy> engineProxies;

  /// Which core this list belongs to.
  final bool simple;

  /// Whether the portal was already carrying traffic when the list asked for numbers.
  final bool wasRunning;

  @override
  ConsumerState<_TcpDelaySweep> createState() => _TcpDelaySweepState();
}

class _TcpDelaySweepState extends ConsumerState<_TcpDelaySweep> {
  /// What the last read said, so the log carries changes instead of a pulse.
  String _lastObservatoryNote = '';

  /// Tags the core reported that this list cannot name, reported once each.
  final Set<String> _unknownTags = <String>{};

  /// The clock that reads the child core's own numbers. Reading is free, measuring is not: the
  /// core times every node itself on the owner's period, and this only asks what it has.
  Timer? _reading;

  @override
  void initState() {
    super.initState();
    _start();
    _reading = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      unawaited(_readObservatory());
    });
  }

  @override
  void dispose() {
    _reading?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TcpDelaySweep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _start();
  }

  /// Reads the child core's numbers, and falls back to a sweep only when no core is running.
  ///
  /// A portal that is up has already timed every node; a portal that is down has nothing to
  /// time with, and then the sweep — its own short-lived core — is the only source left.
  Future<void> _readOrSweep() async {
    await _readObservatory();
    final answered = ref
        .read(tcpDelayProvider)
        .keys
        .any((name) => widget.servers.any((server) => server.name == name));
    if (answered) return;
    await _testDelayWithChild(ref, widget.servers, wasRunning: widget.wasRunning);
  }

  /// Writes what the child core has already timed into the Xray map.
  ///
  /// A row with no delay yet is skipped, not written as a dash: the core says "not measured
  /// yet" for a node it has not reached, and blanking a number it did produce would be a lie
  /// about the node, not about the clock.
  Future<void> _readObservatory() async {
    if (!widget.simple) return;
    if (!ref.read(autoPingProvider).enabled) return;
    final answer = await PortalRuntime.instance.observatory();
    if (!answer.ok || answer.rows.isEmpty) return;
    List<Map<Object?, Object?>> rows;
    try {
      final decoded = jsonDecode(answer.rows);
      if (decoded is! Map) return;
      final list = decoded['rows'];
      if (list is! List) return;
      rows = [
        for (final item in list)
          if (item is Map) item.cast<Object?, Object?>(),
      ];
    } catch (_) {
      return;
    }
    final notifier = ref.read(tcpDelayProvider.notifier);
    var written = 0;
    var alive = 0;
    for (final row in rows) {
      final tag = '${row['tag'] ?? ''}';
      final delay = row['delay'];
      final isAlive = row['alive'] == true;
      if (isAlive) alive++;
      // A node the core has not reached yet has no delay; writing a dash for it would report
      // the clock as if it were the node's.
      if (delay is! num || delay < 0) continue;
      final name = portalNameForTag(widget.servers, tag);
      if (name == null) {
        // A tag the app cannot name is a row that will never show a number: report it once,
        // with the first name the list does know, instead of leaving the list quietly short.
        if (_unknownTags.add(tag)) {
          final first = widget.servers.isEmpty ? '' : widget.servers.first.name;
          commonPrint.log(
            'portal observatory: tag $tag is not in the list '
            '(${widget.servers.length} servers, first $first)',
          );
        }
        continue;
      }
      notifier.record(name, delay.round());
      written++;
    }
    // One line per change, not one per read: the read runs every five seconds and would
    // drown the log it is meant to explain.
    final note = 'rows=${rows.length} alive=$alive written=$written';
    if (note != _lastObservatoryNote) {
      _lastObservatoryNote = note;
      commonPrint.log('portal observatory: $note');
    }
  }

  void _start() {
    final names = [
      if (widget.simple)
        for (final server in widget.servers) server.name
      else
        for (final proxy in widget.engineProxies) proxy.name,
    ];
    if (names.isEmpty) return;
    // Whether this list needs a sweep is the ledger's question, not this widget's: a rebuild
    // recreates the widget, and a recreated widget that always asked began a second sweep
    // that cancelled the one in flight.
    final ledger = widget.simple
        ? ref.read(tcpDelayProvider.notifier).ledger
        : ref.read(engineDelayProvider.notifier).ledger;
    final mode = widget.simple ? Mode.global : Mode.rule;
    final key = names.join('\u0000');
    if (!ledger.shouldStart(mode, key)) return;
    ledger.markStarted(mode, key);
    if (widget.simple) {
      // The child core times its own nodes while the portal is up, so there is nothing to sweep
      // for: read first, and only lift a measurement core when there is no portal to read from.
      unawaited(_readOrSweep());
    } else {
      unawaited(
        _testDelayWithEngine(ref, widget.engineProxies, wasRunning: widget.wasRunning),
      );
    }
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
  bool force = false,
}) async {
  if (proxies.isEmpty) return;
  // Two minutes of a row's own number is good enough: a mode switch fills the gaps instead
  // of re-measuring a list it had just finished.
  final delay = ref.read(engineDelayProvider.notifier);
  final stale = [
    for (final proxy in proxies)
      if (delay.ledger.needsMeasurement(proxy.name, force: force)) proxy,
  ];
  if (stale.isEmpty) {
    commonPrint.log(
      'portal test: every engine row was measured within '
      '${_delayFreshness.inMinutes} minutes, nothing to do',
    );
    return;
  }
  if (wasRunning) {
    await ref.read(proxiesActionProvider.notifier).delayTest(stale, testUrl);
    // The engine answers into its own map; the rows' numbers are taken from there, and each
    // answer is stamped so a switch back does not ask again.
    for (final proxy in stale) {
      final value = ref.read(delayProvider(proxyName: proxy.name));
      delay.record(proxy.name, (value != null && value > 0) ? value : null);
    }
    commonPrint.log(
      'portal test: engine sweep rows=${stale.length}/${proxies.length} '
      'kept_open=yes',
    );
    return;
  }
  final testing = ref.read(delayTestingGroupsProvider.notifier);
  final subject = ref.read(portalGroupProvider) ?? '';
  if (subject.isNotEmpty) testing.start(subject);
  final watch = Stopwatch()..start();
  // This sweep owns the engine it raises, and only for as long as it is still the newest one:
  // the engine is put down in `finally`, so a sweep that has been superseded — a mode switch,
  // an open portal — must not put down the tunnel somebody else is using by then.
  final sweep = delay.beginSweep(Mode.rule);
  final ownerBefore = portalRuntime.status.value.owner;
  final started = await ref.read(setupActionProvider.notifier).setRunning(true);
  var stopped = false;
  try {
    if (!started) {
      final reason = ref.read(setupActionProvider.notifier).lastPortalFailure;
      commonPrint.log(
        'portal test: could not raise the engine${reason.isEmpty ? '' : ': $reason'}',
        logLevel: LogLevel.warning,
      );
      unawaited(
        portalRuntime.noteTest(
          mode: 'rule',
          raised: 'engine',
          durationMs: watch.elapsedMilliseconds,
          stoppedAfter: false,
          detail: 'result=failed${reason.isEmpty ? '' : ' reason=$reason'}',
        ),
      );
      return;
    }
    await _waitForEngine(ref);
    await ref.read(proxiesActionProvider.notifier).delayTest(proxies, testUrl);
  } finally {
    // Only a sweep that still owns what it raised puts it down. Two proofs, because the two
    // ways of being superseded look different: the sweep's own id and mode (a newer sweep, a
    // mode switch), and the owner the runtime reports (something else took the tunnel — the
    // portal, the service, a start the owner asked for). `ownerBefore` is null for a sweep that
    // raised the engine itself, so a runtime that now reports an owner is another owner, and
    // one that reports none is the engine this sweep started.
    final ownerNow = portalRuntime.status.value.owner;
    final stillMine = started &&
        delay.isCurrentSweep(sweep, Mode.rule) &&
        (ownerNow == ownerBefore || (ownerBefore == null && ownerNow == PortalOwner.mihomo));
    if (stillMine) {
      stopped = await ref.read(setupActionProvider.notifier).setRunning(false);
    } else if (started) {
      commonPrint.log(
        'portal test: engine not stopped, the sweep was superseded '
        '(mode=${ref.read(patchClashConfigProvider).mode.name} '
        'owner=${portalRuntime.status.value.owner?.name})',
      );
    }
    watch.stop();
    if (subject.isNotEmpty) testing.stop(subject);
    if (started) {
      unawaited(
        portalRuntime.noteTest(
          mode: 'rule',
          raised: 'engine',
          durationMs: watch.elapsedMilliseconds,
          stoppedAfter: stopped,
          detail: 'result=tests',
        ),
      );
    }
  }
}

/// Times every node of the subscription at once, the way the engine does it.
///
/// One core holds all the nodes and each request is dialled through the node's own tag, so the
/// whole list is measured side by side instead of one restart per node. The sweep runs in the
/// measurement's own core slot, so an open portal keeps carrying traffic while the numbers
/// arrive.
///
/// Rows land in batches as they finish, not all at the end: a sweep of a long subscription is
/// read while it runs, and the figures that are already known should not wait for the slowest
/// node. The whole sweep is bounded by one deadline — past it the remaining rows keep a dash
/// and the core is told to stop.
Future<void> _testDelayWithChild(
  WidgetRef ref,
  List<XrayServerConfig> servers, {
  required bool wasRunning,
  bool force = false,
}) async {
  if (servers.isEmpty) return;
  final measure = measureConfig(servers);
  if (measure.entries.isEmpty) return;
  final delay = ref.read(tcpDelayProvider.notifier);
  final url = ref.read(appSettingProvider).testUrl;
  final watch = Stopwatch()..start();
  // Rows measured less than a minute ago are not asked again: a mode switch is a reason to
  // fill the gaps, not to spend the phone's traffic on numbers that are still true.
  // A press of the test button measures everything in front of the owner: the two-minute
  // window is for the automatic sweep at launch and after a switch, not for a deliberate press.
  final stale = [
    for (final entry in measure.entries)
      if (delay.ledger.needsMeasurement(entry.name, force: force)) entry,
  ];
  if (stale.isEmpty) {
    commonPrint.log(
      'portal test: every row was measured within '
      '${_delayFreshness.inMinutes} minutes, nothing to do',
    );
    return;
  }
  final sweep = delay.beginSweep(Mode.global);
  for (final entry in stale) {
    delay.record(entry.name, null);
  }
  var measured = 0;
  var failure = '';
  // What the owner can see: a sweep of the whole list would spend its first seconds on nodes
  // that are scrolled out of sight. The filter is the app's own, and the list already draws
  // only what it passes.
  final visible = _visibleServerNames(ref);
  try {
    for (var index = 0; index < stale.length; index += _sweepChunk) {
      // A newer sweep — a mode switch, a tap on the other list — owns the map from here.
      if (!delay.isCurrentSweep(sweep, Mode.global)) {
        failure = 'cancelled';
        break;
      }
      if (watch.elapsed > _sweepDeadline) {
        failure = 'deadline';
        break;
      }
      final chunk = stale.skip(index).take(_sweepChunk).toList();
      final answer = await portalRuntime.startMeasure(
        config: measure.config,
        tags: jsonEncode([for (final entry in chunk) entry.tag]),
        url: url,
        timeoutMs: _sweepTimeoutMs,
        limit: _sweepWorkers,
      );
      if (!delay.isCurrentSweep(sweep, Mode.global)) {
        failure = 'cancelled';
        break;
      }
      if (!answer.ok) {
        failure = answer.message;
        commonPrint.log(
          'portal test: the sweep did not run${failure.isEmpty ? '' : ': $failure'}',
          logLevel: LogLevel.warning,
        );
        break;
      }
      failure = measuredError(answer.rows);
      final byTag = {for (final row in parseMeasured(answer.rows)) row.tag: row};
      for (final entry in chunk) {
        final row = byTag[entry.tag];
        if (row == null) continue;
        // A name the list is not drawing keeps its number (it is a fact about the node) but
        // is not counted as what the owner asked for.
        delay.record(entry.name, row.delay);
        if (row.delay != null) {
          measured++;
        } else if (row.error.isNotEmpty) {
          commonPrint.log('portal delay ${entry.name}: ${row.error}');
        }
      }
      if (failure.isNotEmpty) break;
    }
  } finally {
    await portalRuntime.stopMeasure();
    // Nothing to clear: the identifier only grows, so a sweep that has been superseded can
    // never look current again.
    watch.stop();
    commonPrint.log(
      'portal test: sweep rows=${stale.length}/${measure.entries.length} measured=$measured '
      'visible=${visible.length} kept_open=${wasRunning ? 'yes' : 'no'} '
      'duration_ms=${watch.elapsedMilliseconds}'
      '${failure.isEmpty ? '' : ' error=$failure'}',
    );
    unawaited(
      portalRuntime.noteTest(
        mode: 'global',
        raised: 'none',
        durationMs: watch.elapsedMilliseconds,
        stoppedAfter: false,
        detail: 'rows=${stale.length}/${measure.entries.length} measured=$measured'
            ' visible=${visible.length}'
            '${failure.isEmpty ? '' : ' error=$failure'}',
      ),
    );
  }
}

/// The auto-ping period, chosen by the owner.
///
/// Short periods are a real cost on a VPN app — every node is asked in every period, and the
/// battery is the price — so the choices are bounded, and the sentence under them says why the
/// short ones are the expensive ones.
Future<void> _showAutoPingPeriod(BuildContext context, WidgetRef ref) async {
  final l10n = context.appLocalizations;
  final auto = ref.read(autoPingProvider.notifier);
  final current = auto.current;
  final simple =
      ref.read(patchClashConfigProvider.select((s) => s.mode)) == Mode.global;
  // The owner's own list. A minute is the shortest that does not turn a portal into a battery
  // complaint, five minutes is where mihomo's own url-test groups sit.
  final options = <Duration>[
    const Duration(minutes: 1),
    const Duration(seconds: 90),
    const Duration(minutes: 2),
    const Duration(minutes: 3),
    const Duration(minutes: 4),
    const Duration(minutes: 5),
  ];
  final meta = Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
  final picked = await showDialog<Object>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.autoPingPeriod),
      children: [
        // Off is its own choice, not "the smallest number": nothing is asked in the background.
        _periodOption(
          context,
          label: l10n.autoPingOff,
          selected: !current.enabled,
          onTap: () => Navigator.of(context).pop(_AutoPingChoice.off),
        ),
        // "As in the subscription" exists only where a subscription carries such a value —
        // mihomo's url-test groups. Xray has no interval in any subscription, so the switch
        // there is the only owner of the number and this row would be a lie.
        if (!simple)
          _periodOption(
            context,
            label: l10n.autoPingAsInSubscription,
            selected: current.enabled && current.asInSubscription,
            onTap: () => Navigator.of(context).pop(_AutoPingChoice.subscription),
          ),
        for (final option in options)
          _periodOption(
            context,
            label: _periodLabel(l10n, option),
            selected: current.enabled &&
                !current.asInSubscription &&
                current.interval == option,
            onTap: () => Navigator.of(context).pop(option),
          ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 2),
          child: Text(l10n.autoPingHoldHint, style: meta),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
          child: Text(l10n.autoPingPeriodNote, style: meta),
        ),
      ],
    ),
  );
  if (picked == null) return;
  if (picked == _AutoPingChoice.off) {
    auto.setEnabled(false);
  } else if (picked == _AutoPingChoice.subscription) {
    auto.setEnabled(true);
    auto.setAsInSubscription();
  } else if (picked is Duration) {
    auto.setEnabled(true);
    auto.setInterval(picked);
  }
  // The period lives in the document the child was started on, so a live core keeps the old
  // one until it is restarted on the new. The tunnel is not rebuilt for this: the coordinator
  // replaces the core that reads it, which is the same path a row tap takes.
  final status = ref.read(portalStatusProvider);
  if (status.active && status.owner == PortalOwner.xray) {
    unawaited(ref.read(setupActionProvider.notifier).reapplyPortalDocument());
  }
}

/// What the period dialog answered when it was not a period.
enum _AutoPingChoice { off, subscription }

Widget _periodOption(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return SimpleDialogOption(
    onPressed: onTap,
    child: Row(
      children: [
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    ),
  );
}

String _periodLabel(AppLocalizations l10n, Duration value) {
  if (value.inSeconds < 60) return '${value.inSeconds} ${l10n.seconds}';
  if (value.inSeconds % 60 == 0) {
    return '${value.inMinutes} ${l10n.minutes}';
  }
  // 90 s and 150 s are the halves: written as «1.5 min» rather than a mixed unit nobody reads.
  final half = value.inSeconds / 60;
  return '$half ${l10n.minutes}';
}

/// How long a measurement stays good enough to skip.
///
/// Two minutes, not one: a node's reachability does not change in a minute, and a switch
/// back to the mode just left must not re-measure half the list it had just finished. What a
/// switch does is fill the gaps — only rows older than this are asked again.
const _delayFreshness = Duration(minutes: 2);

/// How many nodes one sweep call carries. Small enough that the first numbers land while the
/// list is still being looked at, large enough that a 24-node subscription is three calls.
const _sweepChunk = 6;

/// Full-proxy probes at a time inside one call: Incy's own default, and the pool above which
/// a handshake measures contention rather than the node.
const _sweepWorkers = 4;

const _sweepTimeoutMs = 8000;

/// The whole sweep, however many calls it takes. Past this the rest keep a dash.
const _sweepDeadline = Duration(seconds: 120);

/// The server names the list is drawing right now, for the sweep's log line.
///
/// The sweep itself measures every node — a number is a fact about the node, not about the
/// scroll position — and this only records how many of them the owner could see.
List<String> _visibleServerNames(WidgetRef ref) {
  final filters = ref.watch(portalFiltersProvider);
  final group = ref.read(portalChildRowsProvider)[
      '${ref.read(currentProfileIdProvider) ?? ''}'];
  final visible = portalGroupOfRows(group ?? const <PortalRow>[]);
  return [
    for (final proxy in visible.all)
      if (!filters.hidden.contains(proxy.name)) proxy.name,
  ];
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
    // The strip picks which split-tunnel filter the network mode's list is drawn under, and
    // the filters come from the engine's own config. Without a usable engine format there are
    // no filters to pick — the strip says that instead of offering chips that choose nothing.
    final availability = ref.watch(portalAvailabilityProvider);
    if (!availability.engine.available) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          context.appLocalizations.engineFormatUnusable(
            _availabilityReason(context.appLocalizations, availability.engine),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
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
    // One row, one measurement: the child's server is timed by this process, the engine's is
    // the engine's own delay. Mixing the two is how the engine's rows read single-digit
    // milliseconds to Finland — that handshake went to the engine's fake-IP.
    final measurable =
        widget.xrayServer != null && widget.tcpHost.isNotEmpty && widget.tcpPort > 0;
    // Two cores, two maps: a row's number is read from the map of the core that produced it,
    // so a name present in both subscriptions can never show the other core's value.
    final delay = measurable
        ? ref.watch(tcpDelayProvider)[widget.proxy.name]
        : ref.watch(engineDelayProvider)[widget.proxy.name] ??
            ref.watch(delayProvider(proxyName: node ?? widget.proxy.name));
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
            // One row, timed by the core that already holds every node: the same call the sweep
            // makes, narrowed to this tag. No portal is raised for it and the number cannot be
            // the phone's own latency, because this app's uid is outside the tunnel.
            final server = widget.xrayServer;
            if (server != null) {
              unawaited(
                _testDelayWithChild(
                  ref,
                  [server],
                  wasRunning: ref.read(runTimeProvider) != null,
                  force: true,
                ),
              );
            }
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
                  // Three lines, always three: name with its mark, then the traffic, then the
                  // expiry. One line put three different facts behind one ellipsis, and a
                  // missing field hid the rest; a dash says "the panel sent nothing" instead of
                  // letting the line collapse.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$name ${facts.mark}'.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        facts.traffic,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                      Text(
                        expiry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta,
                      ),
                    ],
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

/// A reason the portal could not move, carried as a sentence the owner can read.
class _PortalSwitchFailure implements Exception {
  const _PortalSwitchFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// How long the record gets to show the new owner before the switch stops asking.
///
/// This is a bound on a question that the start has almost always answered already — it
/// returned only once the owner acknowledged — so it guards against a record that never
/// moves, it does not wait for work to finish. The 12 s that used to sit here was a wait for
/// the engine's config push; that push is a background task now, and its absence must not
/// freeze the screen.
const _modeAckTimeout = Duration(milliseconds: 1500);

/// A switch already in flight **from this screen**. A second tap is dropped rather than
/// queued: two transactions over one portal can only end with the second undoing the first.
///
/// This is only the double-tap guard: the truth is the native coordinator's mutex and
/// generation, which also covers a start from Quick Settings, a revoke and a row tap that
/// never passed through here.
var _portalSwitching = false;

/// Moves the portal between the two modes as one transaction.
///
/// The steps are ordered, not parallel: close the portal, stop the previous core, move the
/// mode, ignite the portal again on the other core, and — returning to the network — wait
/// for the engine to have taken the profile its start pushed. Each step is something that
/// answered, so a failure can be caught where it happened; when one does, the previous mode
/// and core come back and the reason is shown. A switch that half happened would leave a
/// portal carrying nothing with nothing on screen to say why.
Future<void> _switchPortal(WidgetRef ref, {required bool toSimple}) async {
  if (_portalSwitching) return;
  // Another entry's transaction — Quick Settings, the quick action, Always-on — is already
  // moving the portal; this one waits for it rather than racing it, and the tap is simply
  // dropped, which is what the owner asked for by tapping once.
  if (portalRuntime.status.value.busy) return;
  // The mode that is not offered is refused before anything is torn down. Stopping the
  // running portal only to discover that the other mode cannot start leaves the owner with
  // nothing open and a rollback to read; the reason is the whole answer.
  final target = toSimple
      ? ref.read(portalAvailabilityProvider).xray
      : ref.read(portalAvailabilityProvider).engine;
  if (!target.available) {
    final reason = _availabilityReason(currentAppLocalizations, target);
    dialogs.showNotifier(
      toSimple
          ? currentAppLocalizations.portalModeUnavailable(reason)
          : currentAppLocalizations.engineFormatUnusable(reason),
      level: MessageLevel.warning,
    );
    return;
  }
  _portalSwitching = true;
  // The tap is zero for both measurements: the record writes click → `phase=active` from its
  // own hook, the screen writes click → rows once it has them.
  portalSwitchClock.begin(toSimple: toSimple);
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
    // The portal is down, and the child with it: `close` is the coordinator's own stop, so
    // the core has returned from `XrayStop` before the next owner is asked for.
    final stopped = await portalRuntime.close(reason: 'switch');
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
      // The simple portal runs no engine and pushes it no config — that is exactly what "only
      // Xray" means — so on the way back the engine exists only after the start below. A push
      // before it exists answers "config is not applied", and waiting for the mode before the
      // start it belongs to can only time out. The mode is the setting; the start applies the
      // profile (its own forced push), and the wait after it is what proves the engine took it.
      final mode = await setup.pickMode(Mode.rule);
      if (!mode.ok) {
        throw _PortalSwitchFailure(
          mode.cancelled ? 'the switch to the network was cancelled' : mode.reason,
        );
      }
    }
    if (wasRunning) {
      // In the simple portal there is no engine config to wait for: the mode is a setting
      // and the tunnel is the child's, so the start that follows is the whole answer.
      if (!await setup.setRunning(true)) {
        final reason = setup.lastPortalFailure;
        throw _PortalSwitchFailure(
          reason.isEmpty ? 'the portal did not start again' : reason,
        );
      }
      // In the network mode the engine has to have said it holds the tunnel. That answer is
      // the start's own: `open` publishes `Active` only after the owner has its listener, so
      // the switch reads the record rather than polling for a config push that is no longer
      // part of it. A record that never answers is a warning here, not a rollback.
      if (!toSimple) {
        final confirmed = await _awaitMode(Mode.rule);
        if (!confirmed.ok) {
          _reportSwitchUnconfirmed(confirmed.reason);
        }
      }
    }
  } catch (error) {
    // The clock stops before the rollback: a switch that failed is reported as a failure, and
    // the rows the rollback brings back are not this switch's list.
    portalSwitchClock.end();
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

/// Waits for the new owner to acknowledge the tunnel it was given, not for a config push.
///
/// `PortalRuntime.open` answers only after the owner has its own listener or tunnel and the
/// record has published `Active`; that is the whole of what a switch needs to know. The
/// applied inputs are a different question — whether the engine has taken the profile its
/// start pushed — and they are answered by a push that runs in the background. Waiting for
/// that here is what turned a two-hundred-millisecond hand-over into twelve seconds of empty
/// list, so it is not waited for: the record is read, and a record that does not name the
/// new owner within [_modeAckTimeout] is reported rather than turned into a rollback.
Future<PortalCoreResult> _awaitMode(Mode mode) async {
  final deadline = DateTime.now().add(_modeAckTimeout);
  while (true) {
    final status = portalRuntime.status.value;
    if (status.active && status.owner == PortalOwner.mihomo) {
      return const PortalCoreResult.ok();
    }
    if (status.failed && status.owner == PortalOwner.mihomo) {
      return PortalCoreResult.nativeError(status.reason);
    }
    final left = deadline.difference(DateTime.now());
    if (left.isNegative) break;
    await Future<void>.delayed(
      left < const Duration(milliseconds: 50)
          ? left
          : const Duration(milliseconds: 50),
    );
  }
  return PortalCoreResult.nativeError(
    'the engine did not acknowledge ${mode.name} within '
    '${_modeAckTimeout.inMilliseconds} ms',
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
    final stopped = await portalRuntime.close(reason: 'rollback');
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

/// The portal moved but its new owner never said so, in the log and as a notice.
///
/// This is the honest answer to a record that stays on `Starting`, and it is deliberately not
/// a rollback: taking a working portal back down because a log line was slow is worse than
/// the line. The switch is over, the screen is usable, and the reason reaches whoever can act
/// on it — the file, logcat and a warning over the list.
void _reportSwitchUnconfirmed(String reason) {
  commonPrint.log(
    'portal switch unconfirmed: $reason',
    logLevel: LogLevel.warning,
  );
  dialogs.showNotifier(reason, level: MessageLevel.warning);
}
