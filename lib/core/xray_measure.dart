/// Timing every node at once, the way the engine does it.
///
/// mihomo answers a delay test for a whole list in seconds because one core holds every node
/// and opens a temporary connection through the one being asked about. The second core does the
/// same: a document whose outbounds are all of the subscription's nodes, and a dial per node
/// with that node's tag forced on the context (`session.SetForcedOutboundTagToContext` +
/// `core.Dial`). Nothing listens on a port, nothing is restarted, and the tunnel's own instance
/// is untouched — the sweep has its own core slot, so it can run beside an open portal.
///
/// The mechanism is lifted from the clients that already ship it: `XTLS/libXray`
/// (`xray/ping_batch.go`) and `2dust/AndroidLibXrayLite` (`libv2ray_utils.go`).
library;

import 'dart:convert';

import 'xray_subscription.dart';

/// A measurement document for [servers] plus the tag of every node in it.
///
/// The panel's own element is passed through per node: its first real outbound is the node, and
/// anything it declares about that node (transport, tls, headers) is kept untouched. What the
/// document adds is only a unique tag, so the sweep can name the node it is timing.
({String config, List<({String name, String tag})> entries}) measureConfig(
  List<XrayServerConfig> servers,
) {
  final entries = <({String name, String tag})>[];
  final outbounds = <Map<String, Object?>>[];
  for (var index = 0; index < servers.length; index++) {
    final server = servers[index];
    final node = _nodeOutbound(server.config);
    if (node == null) continue;
    final tag = 'node-$index';
    outbounds.add({...node, 'tag': tag});
    entries.add((name: server.name, tag: tag));
  }
  outbounds.add({'tag': 'blocked', 'protocol': 'blackhole'});
  return (
    config: const JsonEncoder.withIndent(' ').convert({
      'log': {'loglevel': 'warning'},
      'outbounds': outbounds,
    }),
    entries: entries,
  );
}

/// The node outbound of one server's document, without the tag it was given there.
Map<String, Object?>? _nodeOutbound(Object? config) {
  Object? document = config;
  if (config is String) {
    try {
      document = jsonDecode(config);
    } catch (_) {
      return null;
    }
  }
  if (document is! Map) return null;
  final outbounds = document['outbounds'];
  if (outbounds is! List) return null;
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}'.toLowerCase();
    // A blackhole, a freedom outbound or a balancer is not a node; the first real proxy is.
    if (protocol.isEmpty || protocol == 'blackhole' || protocol == 'freedom') continue;
    if (item.containsKey('balancers') || item.containsKey('selector')) continue;
    return Map<String, Object?>.from(item);
  }
  return null;
}

/// One answer from the sweep.
class MeasuredNode {
  const MeasuredNode({required this.tag, required this.delay, this.error = ''});

  final String tag;

  /// Milliseconds, or null when the node did not answer.
  final int? delay;

  final String error;
}

/// Reads the core's answer: `{"rows":[...]}` on success, `{"error":"..."}` on a fault.
///
/// A row's `delay` below zero is the core naming the failure (-1 refused or failed, -2 timed
/// out); both become "no number", and the reason stays in the log rather than on the row.
List<MeasuredNode> parseMeasured(String raw) {
  Object? document;
  try {
    document = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (document is! Map) return const [];
  final rows = document['rows'];
  if (rows is! List) return const [];
  return [
    for (final row in rows)
      if (row is Map)
        MeasuredNode(
          tag: '${row['tag'] ?? ''}',
          delay: (row['delay'] is num && (row['delay'] as num) > 0)
              ? (row['delay'] as num).toInt()
              : null,
          error: '${row['error'] ?? ''}',
        ),
  ];
}

/// The core's own words when the sweep itself failed.
String measuredError(String raw) {
  try {
    final document = jsonDecode(raw);
    if (document is Map) return '${document['error'] ?? ''}';
  } catch (_) {
    return '';
  }
  return '';
}
