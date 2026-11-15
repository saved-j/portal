import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Where each engine server actually listens.
///
/// The engine will not say: its API lists names and delay history, never addresses. The
/// subscription body does carry them, so they are read once when the profile updates and
/// kept beside it — that is what lets the row time a TCP handshake instead of asking a
/// core that has no answer.
class ProxyEndpoint {
  const ProxyEndpoint(this.host, this.port);

  final String host;
  final int port;

  bool get isUsable => host.isNotEmpty && port > 0;

  Map<String, Object?> toJson() => {'host': host, 'port': port};

  static ProxyEndpoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final host = '${json['host'] ?? ''}'.trim();
    final port = switch (json['port']) {
      final int value => value,
      final Object value => int.tryParse(value.toString()) ?? 0,
      null => 0,
    };
    if (host.isEmpty || port <= 0) return null;
    return ProxyEndpoint(host, port);
  }
}

/// Reads `proxies: [{name, server, port}]` from a subscription body.
///
/// A body that is not YAML, or carries no proxies, yields an empty map: unknown is a dash,
/// never a guess.
Map<String, ProxyEndpoint> parseProxyEndpoints(String body) {
  final text = body.trim();
  if (text.isEmpty) return const {};
  Object? document;
  try {
    document = loadYaml(text);
  } catch (_) {
    return const {};
  }
  if (document is! Map) return const {};
  final proxies = document['proxies'];
  if (proxies is! List) return const {};

  final result = <String, ProxyEndpoint>{};
  for (final item in proxies) {
    if (item is! Map) continue;
    final name = '${item['name'] ?? ''}'.trim();
    final host = '${item['server'] ?? ''}'.trim();
    final port = switch (item['port']) {
      final int value => value,
      final Object value => int.tryParse(value.toString()) ?? 0,
      null => 0,
    };
    if (name.isEmpty || host.isEmpty || port <= 0) continue;
    result[name] = ProxyEndpoint(host, port);
  }
  return result;
}

/// Writes the endpoints beside the profile, so the next launch still knows them.
Future<void> saveProxyEndpoints(
  String profilePath,
  Map<String, ProxyEndpoint> endpoints,
) async {
  final file = File('$profilePath.endpoints.json');
  try {
    if (endpoints.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.writeAsString(
      jsonEncode({
        for (final entry in endpoints.entries) entry.key: entry.value.toJson(),
      }),
    );
  } catch (_) {
    // A cache that cannot be written is not worth failing an update over.
  }
}

/// The endpoints saved for this profile, empty when none were saved yet.
Future<Map<String, ProxyEndpoint>> loadProxyEndpoints(
  String profilePath,
) async {
  final file = File('$profilePath.endpoints.json');
  try {
    if (!await file.exists()) return const {};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return const {};
    final result = <String, ProxyEndpoint>{};
    for (final entry in decoded.entries) {
      final endpoint = ProxyEndpoint.fromJson(entry.value);
      if (endpoint != null) result['${entry.key}'] = endpoint;
    }
    return result;
  } catch (_) {
    return const {};
  }
}
