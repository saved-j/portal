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

Group portalGroupOfRows(List<PortalRow> rows) => Group(
      type: GroupType.Selector,
      name: portalRowsGroupName,
      all: [
        for (final row in rows)
          if (!isBuiltinOutboundName(row.name)) row.toProxy(),
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
  final proxies = document['proxies'];
  if (proxies is! List) return const [];
  final rows = <PortalRow>[];
  final seen = <String>{};
  for (final item in proxies) {
    if (item is! Map) continue;
    final name = '${item['name'] ?? ''}'.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    if (isBuiltinOutboundName(name)) continue;
    rows.add(
      PortalRow(
        name: name,
        type: '${item['type'] ?? ''}'.trim(),
      ),
    );
  }
  return rows;
}

/// The group the list draws while a switch is in flight.
///
/// [live] is what the owner of the moment answered — the engine's groups in the network
/// mode, the child's servers in the portal. An empty answer never replaces what is on
/// screen: those rows are a name, a protocol and a ping, all of them still true, and an
/// empty list in the middle of a switch reads as an empty subscription. When nothing has
/// ever answered, the profile's own `proxies:` are the rows. Only a profile that has no
/// proxies at all ends in no group, which is the honest empty state.
Group? portalShownGroup({
  required Group? live,
  required Group? held,
  required List<PortalRow> profileRows,
  void Function(Group)? remember,
}) {
  if (live != null && live.all.isNotEmpty) {
    remember?.call(live);
    return live;
  }
  if (held != null && held.all.isNotEmpty) return held;
  final fromProfile = portalGroupOfRows(profileRows);
  if (fromProfile.all.isNotEmpty) return fromProfile;
  return live;
}

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
