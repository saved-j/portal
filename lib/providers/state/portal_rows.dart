part of '../state.dart';

/// One server row, as it can be drawn without asking any core.
///
/// A name, its protocol and the panel's description: exactly what the profile already
/// carries in its own `proxies:`. Nothing here needs a running engine, a pushed config or a
/// delay measurement, which is the point — during a switch there is a moment when no core
/// can answer, and that moment must not look like an empty subscription.
class PortalRow {
  const PortalRow({required this.name, this.type = '', this.description = ''});

  final String name;
  final String type;

  /// The line the panel wrote for this server, when it wrote one.
  final String description;

  Proxy toProxy() => Proxy(
        name: name,
        type: type,
        serverDescription: description.isEmpty ? name : description,
      );
}

/// The group a list of rows is drawn as.
///
/// The list widget is shaped around a [Group]: it needs a name, a `now` and members. These
/// rows have no group of their own — they are the profile's servers, not any core's group —
/// so they get the portal's own group name, and the same name the simple portal already
/// uses. Nothing is written to the engine with it.
const portalRowsGroupName = 'PORTAL';

/// Names this app itself used to inject into the engine's config.
///
/// `XRAY-SOCKS` and `PORTAL-XRAY` came from the abandoned local bridge (`lib/core/xray_bridge_config.dart`)
/// and were pushed into every engine config until patch 28 removed the injector. A build that
/// still holds that config in memory, or a list remembered from before the upgrade, must not
/// draw them: they are not servers of the subscription and never were. The filter lives here,
/// on the one path every row source goes through, so a row cannot come back through a cache.
const _portalServiceNodeNames = {'XRAY-SOCKS', 'PORTAL-XRAY'};

/// True for a name that is this app's own machinery rather than a node of the subscription.
bool isPortalServiceNode(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return true;
  return _portalServiceNodeNames.contains(trimmed.toUpperCase());
}

Group portalGroupOfRows(List<PortalRow> rows) => Group(
      type: GroupType.Selector,
      name: portalRowsGroupName,
      all: [
        for (final row in rows)
          if (!isBuiltinOutboundName(row.name) && !isPortalServiceNode(row.name))
            row.toProxy(),
      ],
    );

/// Reads `proxies:` out of a subscription body, for the rows a fresh install has no other
/// source for.
///
/// The engine's groups arrive only after a config has been applied, and the child's list only
/// after its subscription file has been read; before either, the file itself is the honest
/// source and it is already on disk.
List<PortalRow> parsePortalRows(String body) {
  final text = body.trim();
  if (text.isEmpty) return const [];
  Object? document;
  try {
    document = loadYaml(text);
  } catch (_) {
    return const [];
  }
  if (document is! Map) return const [];
  // Rows are the members of the panel's own group, in the order the panel wrote them — the way
  // the engine's answer draws the same list. That is what puts `⚡️ Auto Europe` and its siblings
  // above the servers: they are members of the main group before any server is. Groups that are
  // named after routing rules stay on the strip, because they are not members of this one.
  final groups = document['proxy-groups'];
  final proxies = document['proxies'];
  final rows = <PortalRow>[];
  final seen = <String>{};
  final proxyTypes = <String, String>{
    if (proxies is List)
      for (final item in proxies)
        if (item is Map && '${item['name'] ?? ''}'.trim().isNotEmpty)
          '${item['name']}'.trim(): '${item['type'] ?? ''}'.trim(),
  };
  final groupTypes = <String, String>{
    if (groups is List)
      for (final item in groups)
        if (item is Map && '${item['name'] ?? ''}'.trim().isNotEmpty)
          '${item['name']}'.trim(): '${item['type'] ?? ''}'.trim(),
  };
  if (groups is List) {
    for (final group in groups) {
      if (group is! Map) continue;
      final members = group['proxies'];
      if (members is! List || members.isEmpty) continue;
      for (final member in members) {
        final name = '$member'.trim();
        if (name.isEmpty || !seen.add(name)) continue;
        if (isBuiltinOutboundName(name) || isPortalServiceNode(name)) continue;
        // A member that is a group carries the group's own type, so the row can say what it is.
        rows.add(
          PortalRow(
            name: name,
            type: proxyTypes[name] ?? groupTypes[name] ?? '',
          ),
        );
      }
      break;
    }
  }
  if (rows.isNotEmpty) return rows;
  if (proxies is! List) return const [];
  for (final item in proxies) {
    if (item is! Map) continue;
    final name = '${item['name'] ?? ''}'.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    if (isBuiltinOutboundName(name) || isPortalServiceNode(name)) continue;
    rows.add(
      PortalRow(
        name: name,
        type: '${item['type'] ?? ''}'.trim(),
      ),
    );
  }
  return rows;
}

/// The simple portal's rows: the child's own servers, named by the child's document.
///
/// The list, the row and the mode control are all shaped around a [Group], and in this mode
/// no engine holds one, so the group is made here — from the Xray document and nothing else.
/// It is never written to the engine, and it never carries an engine proxy name.
Group portalGroupOfServers(List<XrayServerConfig> servers) => Group(
      type: GroupType.Selector,
      name: portalRowsGroupName,
      all: [
        for (final server in servers)
          Proxy(
            name: server.name,
            type: server.protocol,
            serverDescription: server.label,
          ),
      ],
    );

/// The rows one mode can draw with no core answering, from that mode's own source.
///
/// The two modes read the same subscription in two different formats: the simple portal's
/// names are the Xray document's servers, the network mode's are the engine document's
/// `proxies:`. Handing one mode the other's rows is how a switch showed the portal's nodes
/// under 'Сеть порталов' — each name was real, the list was not.
Group? portalFallbackGroup({
  required bool simple,
  required List<XrayServerConfig> servers,
  required List<PortalRow> engineRows,
}) {
  if (simple) {
    if (servers.isEmpty) return null;
    return portalGroupOfServers(servers);
  }
  final fromEngine = portalGroupOfRows(engineRows);
  return fromEngine.all.isEmpty ? null : fromEngine;
}

/// The engine's own rows, kept per profile for as long as the app runs.
///
/// A closed portal has no groups to ask, and the profile's `proxies:` are the same document
/// the engine last applied — so they are a good answer, and the last answer the engine
/// actually gave is a better one. It is remembered under the profile it came from: another
/// profile's servers are a different list, and the network mode never draws the child's.
class PortalEngineRowsNotifier extends Notifier<Map<String, List<PortalRow>>> {
  /// The build the remembered rows were made under.
  ///
  /// The memory itself cannot outlive the process, but the *meaning* of the names in it can
  /// change with a build — that is exactly what happened when the bridge's injected group was
  /// removed while the engine still held the config that carried it. Stamping the build makes
  /// the invalidation explicit instead of relying on a restart, and costs nothing: a mismatch
  /// empties the map once, on the first launch of a new build.
  static const _build = String.fromEnvironment('APP_VERSION');

  String _stamp = '';

  @override
  Map<String, List<PortalRow>> build() => const {};

  void remember({required String profileId, required Group group}) {
    if (_stamp != _build) {
      _stamp = _build;
      if (state.isNotEmpty) state = const {};
    }
    if (profileId.isEmpty || group.all.isEmpty) return;
    final rows = <PortalRow>[
      for (final proxy in group.all)
        // A built-in (DIRECT/REJECT) and this app's own service nodes are not servers of the
        // subscription, however real the group that carries them looks.
        if (!isBuiltinOutboundName(proxy.name) && !isPortalServiceNode(proxy.name))
          PortalRow(
            name: proxy.name,
            type: proxy.type,
            description: proxy.serverDescription ?? proxy.name,
          ),
    ];
    if (rows.isEmpty) return;
    state = {...state, profileId: rows};
  }
}

final portalEngineRowsProvider =
    NotifierProvider<PortalEngineRowsNotifier, Map<String, List<PortalRow>>>(
        PortalEngineRowsNotifier.new);

/// The child's own list, remembered per profile.
///
/// The engine has its cache and the child has its own — two documents, two cores, two lists.
/// A row remembered here is a server of the xray body and nothing else; the network mode never
/// reads this map, and the simple portal never reads the engine's. Keeping them apart is the
/// whole point: a name means nothing without the core that answered it.
class PortalChildRowsNotifier extends Notifier<Map<String, List<PortalRow>>> {
  static const _build = String.fromEnvironment('APP_VERSION');

  String _stamp = '';

  @override
  Map<String, List<PortalRow>> build() => const {};

  void remember({required String profileId, required List<XrayServerConfig> servers}) {
    if (_stamp != _build) {
      _stamp = _build;
      if (state.isNotEmpty) state = const {};
    }
    if (profileId.isEmpty || servers.isEmpty) return;
    final rows = <PortalRow>[
      for (final server in servers)
        if (!isBuiltinOutboundName(server.name) && !isPortalServiceNode(server.name))
          PortalRow(
            name: server.name,
            type: server.protocol,
            description: server.address,
          ),
    ];
    if (rows.isEmpty) return;
    state = {...state, profileId: rows};
  }
}

final portalChildRowsProvider =
    NotifierProvider<PortalChildRowsNotifier, Map<String, List<PortalRow>>>(
        PortalChildRowsNotifier.new);

/// Which core's rows these are.
///
/// The two lists are two documents and two owners. A name is a name in both, so the owner is
/// the only thing that says whose row it is — and a group left in memory by a core that has
/// stopped is not an answer from that core.
enum RowsOwner {
  engine('engine'),
  child('child');

  const RowsOwner(this.label);

  final String label;
}

/// The panel's own note for each server, keyed by name.
///
/// The same subscription carries the notes only in the document the second core is served
/// (`meta.serverDescription`); the engine's YAML has the names and nothing about them. The two
/// documents describe the same servers, so the notes are read once from whichever one has
/// them and handed to the rows of both — that is what makes the comment of the Xray list
/// appear in the network list without the engine ever learning a word about it.
///
/// A name is only matched to a note when both sides are the same string after the flag is
/// dropped: «🇪🇪 Эстония» and «Эстония» are the same server, «Эстония» and «Эстония 2» are not.
class PortalNoteIndex {
  const PortalNoteIndex(this._notes);

  const PortalNoteIndex.empty() : _notes = const {};

  final Map<String, String> _notes;

  static final _flag = RegExp(
    r'^[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\s]+',
    unicode: true,
  );

  /// The name as it is compared: no leading flag, no emoji, no extra spaces.
  static String keyOf(String name) =>
      name.replaceFirst(_flag, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Builds the index from the second core's document, which is where the notes are.
  factory PortalNoteIndex.ofServers(List<XrayServerConfig> servers) => PortalNoteIndex({
        for (final server in servers)
          if (server.description.isNotEmpty) keyOf(server.name): server.description,
      });

  String noteFor(String name) => _notes[keyOf(name)] ?? '';

  bool get isEmpty => _notes.isEmpty;
}

/// The panel's notes for this profile, from its Xray document.
///
/// Read once per profile and reused by both lists: a row in the network list is the same
/// server as a row in the simple portal, and the note belongs to the server, not to the
/// format it was delivered in.
final portalNoteIndexProvider = FutureProvider.autoDispose<PortalNoteIndex>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const PortalNoteIndex.empty();
  final body = await profile.readXrayFormat();
  if (body == null) return const PortalNoteIndex.empty();
  return PortalNoteIndex.ofServers(parseXraySubscription(body));
});

/// A group and the owner it came from.
typedef OwnedGroup = ({Group group, RowsOwner owner});

/// The rows the list draws right now, whose they are, and which core answered.
///
/// [mode] is the owner this mode draws from, and nothing from the other one can be returned:
///
/// * [live] is the current owner's own answer, and it counts only when its [OwnedGroup.owner]
///   is [mode] — a mode is not allowed to read the other core's group, however fresh it is.
/// * [held] is the last group this mode drew, kept per owner by the caller, and only the
///   mode's own held group is read.
/// * [fallbacks] are the sources this mode can draw with no core answering, in the order it
///   trusts them, each with the name the transition log will carry for it.
///
/// Only an owner that is holding the tunnel now may answer `live`; the caller decides that.
/// An empty group is not an answer, and a mode with no rows at all ends in no group, which is
/// the honest empty state.
PortalShown portalShownRows({
  required RowsOwner mode,
  required OwnedGroup? live,
  required OwnedGroup? held,
  required List<(String, Group?)> fallbacks,
  void Function(OwnedGroup)? remember,
}) {
  final ownLive = live != null && live.owner == mode ? live.group : null;
  if (ownLive != null && ownLive.all.isNotEmpty) {
    remember?.call((group: ownLive, owner: mode));
    return (group: ownLive, source: 'live', owner: mode);
  }
  final ownHeld = held != null && held.owner == mode ? held.group : null;
  if (ownHeld != null && ownHeld.all.isNotEmpty) {
    return (group: ownHeld, source: 'held', owner: mode);
  }
  for (final (source, group) in fallbacks) {
    if (group != null && group.all.isNotEmpty) {
      return (group: group, source: source, owner: mode);
    }
  }
  return (group: null, source: 'none', owner: mode);
}

/// A group, where its rows came from (`live`, `held`, `cache`, `profile` or `servers`), and
/// which core's rows they are.
typedef PortalShown = ({Group? group, String source, RowsOwner owner});

/// The current profile's own servers: the last resort of the list, and never a guess.
final profilePortalRowsProvider =
    FutureProvider.autoDispose<List<PortalRow>>((ref) async {
  final profile = ref.watch(currentProfileProvider);
  if (profile == null) return const [];
  try {
    final file = await profile.file;
    if (!await file.exists()) return const [];
    return parsePortalRows(await file.readAsString());
  } catch (_) {
    // An unreadable profile is not a list of servers; the caller keeps what it had.
    return const [];
  }
});
