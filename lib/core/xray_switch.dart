import 'dart:io';

import 'package:yaml/yaml.dart';

/// Finds the node the owner picked, inside the config the engine is already running.
///
/// The applied config is the one source that carries every subscription node in full: the
/// app-level model keeps only names and descriptions, and the profile's raw response is not
/// retained. Reading it here means the child process gets exactly the node the engine would
/// have used, including keys this file knows nothing about.
///
/// Returns null when the pick is a builtin (DIRECT/REJECT) or resolves to nothing, so the
/// caller can refuse to switch rather than start a child that cannot work.
Future<Map<String, dynamic>?> nodeDefinitionFor(
  String configPath,
  String name, {
  int depth = 3,
}) async {
  final file = File(configPath);
  if (!file.existsSync()) return null;
  final document = loadYaml(await file.readAsString());
  if (document is! Map) return null;

  final direct = _findProxy(document, name);
  if (direct != null) return direct;
  final member = _memberOf(document, name, depth);
  if (member == null) return null;
  return _findProxy(document, member);
}

Map<String, dynamic>? _findProxy(Map document, String name) {
  final proxies = document['proxies'];
  if (proxies is! List) return null;
  for (final item in proxies) {
    if (item is Map && '${item['name']}' == name) {
      return item.map((key, value) => MapEntry('$key', value));
    }
  }
  return null;
}

/// A group stands for its first real member; 'Auto' and friends must be opened before a
/// node can be handed to Xray.
String? _memberOf(Map document, String name, int depth) {
  if (depth <= 0) return null;
  final groups = document['proxy-groups'];
  if (groups is! List) return null;
  for (final group in groups) {
    if (group is! Map || '${group['name']}' != name) continue;
    final members = group['proxies'];
    if (members is! List) return null;
    for (final member in members) {
      final text = '$member';
      if (text == 'DIRECT' || text == 'REJECT') continue;
      if (_findProxy(document, text) != null) return text;
      final nested = _memberOf(document, text, depth - 1);
      if (nested != null) return nested;
    }
  }
  return null;
}

/// The names the subscription uses for its servers, keyed by address.
///
/// A panel may tag its Xray nodes `auto-N` and keep the readable name only in the engine's
/// build of the same subscription. Both builds point at the same servers, so the address is
/// what joins them.
Future<Map<String, String>> serverNamesByAddress(String configPath) async {
  final file = File(configPath);
  if (!file.existsSync()) return const {};
  final document = loadYaml(await file.readAsString());
  if (document is! Map) return const {};
  final proxies = document['proxies'];
  if (proxies is! List) return const {};
  final names = <String, String>{};
  for (final item in proxies) {
    if (item is! Map) continue;
    final server = '${item['server'] ?? ''}';
    final name = '${item['name'] ?? ''}';
    if (server.isNotEmpty && name.isNotEmpty) names[server] = name;
  }
  return names;
}
