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
/// The request is the app's own test URL, so the number is comparable with the engine's
/// URLTEST; the clock starts before the socks handshake because that handshake is the node's
/// own work. No answer within [timeout] is no number at all.
Future<int?> measureNode({
  required int port,
  required String url,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final targetPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final path = uri.path.isEmpty ? '/' : uri.path;
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect('127.0.0.1', port, timeout: timeout);
    socket.add(_socks5Connect(uri.host, targetPort));
    final answer = await _readSocksReply(socket, timeout);
    if (!answer) return null;
    socket.write(
      'GET $path HTTP/1.1\r\n'
      'Host: ${uri.host}\r\n'
      'User-Agent: portal-delay\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    final first = await socket.first.timeout(timeout);
    watch.stop();
    return first.isEmpty ? null : watch.elapsedMilliseconds;
  } on TimeoutException {
    return null;
  } on SocketException {
    return null;
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }
}

/// A socks5 greeting and a CONNECT to [host]:[port], with no authentication.
List<int> _socks5Connect(String host, int port) {
  final name = utf8.encode(host);
  return [
    0x05, 0x01, 0x00, // version, one method, "no authentication"
    0x05, 0x01, 0x00, // version, CONNECT, reserved
    0x03, name.length, ...name, // domain name
    (port >> 8) & 0xFF, port & 0xFF,
  ];
}

/// Reads the socks reply; true when the node accepted the connection.
Future<bool> _readSocksReply(Socket socket, Duration timeout) async {
  final buffer = <int>[];
  await for (final chunk in socket.timeout(timeout)) {
    buffer.addAll(chunk);
    if (buffer.length < 2) continue;
    if (buffer[0] != 0x05) return false;
    if (buffer[1] != 0x00) return false;
    // The bound address follows the status byte: read it so the request starts on a clean
    // stream, then let the caller write.
    final addressType = buffer.length > 3 ? buffer[3] : -1;
    final needed = switch (addressType) {
      0x01 => 10,
      0x03 => buffer.length > 4 ? 7 + buffer[4] : -1,
      0x04 => 22,
      _ => -1,
    };
    if (needed > 0 && buffer.length >= needed) return true;
  }
  return false;
}
