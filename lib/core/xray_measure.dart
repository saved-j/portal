/// Timing every node at once, the way the engine does it.
///
/// mihomo answers a delay test for a whole list in seconds because one core holds every node
/// and opens a temporary connection through the one being asked about. The second core can do
/// the same: started on a document whose outbounds are all of the subscription's nodes, each
/// behind its own local socks inbound, a request to one port is served by one node. The tunnel
/// is not involved and the portal is not moved — the sweep is a second, short-lived core.
///
/// Nothing here guesses: a port that answers means the node carried a real request to a real
/// host, and the number is the time to the first byte that came back.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'xray_subscription.dart';

/// The port the first node's socks inbound listens on. Every following node takes the next.
const int measureBasePort = 20000;

/// A measurement document for [servers], with one socks inbound per node.
///
/// The panel's own document is passed through per node: its first outbound is the node, and
/// anything it declares about that node (transport, tls, headers) is kept untouched. What is
/// added is the mapping from a local port to that outbound, which is the only thing the sweep
/// needs.
({String config, List<({String name, int port})> entries}) measureConfig(
  List<XrayServerConfig> servers,
) {
  final entries = <({String name, int port})>[];
  final inbounds = <Map<String, Object?>>[];
  final outbounds = <Map<String, Object?>>[];
  final rules = <Map<String, Object?>>[];
  for (var index = 0; index < servers.length; index++) {
    final server = servers[index];
    final node = _firstOutbound(server.config);
    if (node == null) continue;
    final tag = 'node-$index';
    final inboundTag = 'measure-$index';
    outbounds.add({...node, 'tag': tag});
    entries.add((name: server.name, port: measureBasePort + index));
    inbounds.add({
      'tag': inboundTag,
      'listen': '127.0.0.1',
      'port': measureBasePort + index,
      'protocol': 'socks',
      'settings': {'udp': false},
    });
    rules.add({
      'type': 'field',
      'inboundTag': [inboundTag],
      'outboundTag': tag,
    });
  }
  outbounds.add({'tag': 'blocked', 'protocol': 'blackhole'});
  final document = const JsonEncoder.withIndent(' ').convert({
    'log': {'loglevel': 'warning'},
    'inbounds': inbounds,
    'outbounds': outbounds,
    'routing': {'domainStrategy': 'AsIs', 'rules': rules},
  });
  return (config: document, entries: entries);
}

/// The node outbound of one server's document, without the tag it was given there.
Map<String, Object?>? _firstOutbound(Object? config) {
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
    // A blackhole or a direct outbound is not a node; the first real proxy is.
    if (protocol.isEmpty || protocol == 'blackhole' || protocol == 'freedom') continue;
    return Map<String, Object?>.from(item);
  }
  return null;
}

/// One node's round trip, measured by asking it through its own socks port.
///
/// One subscription to the socket carries the whole conversation — greeting reply, connect
/// reply, the request, then the first byte back. Listening twice is what a first version did,
/// and a single-subscription socket cannot be listened to twice: every row came back empty
/// while the core's own log showed it dialling the node. The clock starts before the handshake
/// because that handshake is the node's own work.
Future<int?> measureNode({
  required int port,
  required String url,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final targetPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final path = uri.path.isEmpty ? '/' : uri.path;
  final request = 'GET $path HTTP/1.1\r\n'
      'Host: ${uri.host}\r\n'
      'User-Agent: portal-delay\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n';
  Socket? socket;
  StreamSubscription<Uint8List>? subscription;
  Timer? watchdog;
  final done = Completer<int?>();
  final watch = Stopwatch()..start();
  final buffer = <int>[];
  var stage = 0; // 0 greeting, 1 connect, 2 request sent
  try {
    socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
    watchdog = Timer(timeout, () {
      if (!done.isCompleted) done.complete(null);
    });
    void finish(int? value) {
      if (!done.isCompleted) done.complete(value);
    }

    final open = socket;
    subscription = open.listen(
      (chunk) {
        buffer.addAll(chunk);
        if (stage == 0) {
          if (buffer.length < 2) return;
          if (buffer[0] != 0x05 || buffer[1] != 0x00) {
            finish(null);
            return;
          }
          buffer.clear();
          stage = 1;
          open.write(_socksConnect(uri.host, targetPort));
          open.flush().catchError((_) {});
          return;
        }
        if (stage == 1) {
          final end = _socksReplyEnd(buffer);
          if (end == 0) return;
          if (end < 0) {
            finish(null);
            return;
          }
          buffer.clear();
          stage = 2;
          open.write(request);
          open.flush().catchError((_) {});
          return;
        }
        // The first byte back through the node is the number.
        finish(buffer.isEmpty ? null : watch.elapsedMilliseconds);
      },
      onError: (_) => finish(null),
      onDone: () => finish(null),
      cancelOnError: true,
    );
    open.write([0x05, 0x01, 0x00]);
    await open.flush();
    return await done.future;
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  } catch (_) {
    return null;
  } finally {
    watchdog?.cancel();
    await subscription?.cancel();
    socket?.destroy();
  }
}

/// A socks5 CONNECT to [host]:[port] with no authentication, after the greeting was answered.
List<int> _socksConnect(String host, int port) {
  final name = utf8.encode(host);
  return [
    0x05, 0x01, 0x00, // version, CONNECT, reserved
    0x03, name.length, ...name, // domain name
    (port >> 8) & 0xFF, port & 0xFF,
  ];
}

/// Where the connect reply ends in [buffer]: its length, 0 while it is still arriving, -1 when
/// the node refused the connection.
int _socksReplyEnd(List<int> buffer) {
  if (buffer.length < 5) return 0;
  if (buffer[0] != 0x05 || buffer[1] != 0x00) return -1;
  final total = switch (buffer[3]) {
    0x01 => 10,
    0x03 => buffer.length > 4 ? 7 + buffer[4] : 0,
    0x04 => 22,
    _ => -1,
  };
  if (total <= 0) return total;
  return buffer.length >= total ? total : 0;
}
