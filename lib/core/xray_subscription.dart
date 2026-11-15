import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

/// A subscription body as the Xray clients understand it.
///
/// Documented by the Incy developer docs: a JSON subscription is either one full xray
/// configuration or an **array of them**, and each element of the array is a separate
/// server. The name of that server is the tag of its first proxy outbound; its description
/// comes from `meta.serverDescription`. Anything else in the document is passed to the core
/// untouched.
class XrayServerConfig {
  const XrayServerConfig({
    required this.name,
    required this.config,
    required this.protocol,
    this.description = '',
    this.flag = '',
    this.address = '',
    this.port = 0,
  });

  final String name;
  final String description;
  final String flag;

  /// Where the server listens. The row pings this address directly: the engine never holds
  /// these servers, so asking it for a delay could only ever answer "timeout".
  final String address;
  final int port;

  /// The protocol of the outbound that carries traffic — `vless`, `hysteria2`, `trojan`.
  ///
  /// It is inside the configuration, not beside it: a full config states its protocol per
  /// outbound, so reading it here is the only honest source instead of labelling every
  /// server of this format `xray`.
  final String protocol;

  /// The whole configuration for this one server, ready to be handed to the core.
  final Map<String, dynamic> config;

  /// `🇪🇪 Эстония · Максимальная скорость`, the line the owner reads.
  String get label {
    final head = flag.isEmpty ? name : '$flag $name';
    return description.isEmpty ? head : '$head · $description';
  }
}

/// Reads every server out of a subscription body.
///
/// Returns an empty list for a body that is not JSON or carries no configuration, so a
/// broken answer never looks like a subscription with zero problems.
List<XrayServerConfig> parseXraySubscription(String body) {
  final text = body.trim();
  if (text.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    return const [];
  }

  final configs = <Map<String, dynamic>>[];
  if (decoded is List) {
    for (final item in decoded) {
      if (item is Map && _isFullConfig(item)) {
        configs.add(Map<String, dynamic>.from(item));
      }
    }
  } else if (decoded is Map && _isFullConfig(decoded)) {
    configs.add(Map<String, dynamic>.from(decoded));
  }
  if (configs.isEmpty) return const [];

  // The panel names each configuration in `remarks`; logged once so the shape is visible.
  for (final config in configs.take(3)) {
    debugPrint('xray remarks: ${config['remarks']}');
  }

  final servers = <XrayServerConfig>[];
  for (var index = 0; index < configs.length; index++) {
    final config = configs[index];
    final meta = config['meta'];
    final map = meta is Map ? meta : const {};
    // The panel writes the whole line in `remarks`: `🇪🇪 Эстония · Максимальная скорость`.
    // Its first segment is the name, the rest is what the server is for.
    // Per the format docs the panel writes the whole line in top-level `remarks`, as
    // `🇵🇱 Poland | TCP` or `🇪🇪 Эстония · Максимальная скорость`: flag and name first,
    // then what the server is for after the separator.
    final remarks = '${config['remarks'] ?? ''}'.trim();
    final parts = remarks.split(RegExp(r'\s*[·|]\s*'));
    final remarkName = parts.isEmpty ? '' : parts.first.trim();
    final remarkNote = parts.length > 1 ? parts.skip(1).join('·').trim() : '';
    final transport = _transportOf(config);
    final endpoint = _endpointOf(config);
    servers.add(
      XrayServerConfig(
        protocol: _protocolOf(config),
        name: remarkName.isNotEmpty ? remarkName : (_firstProxyTag(config) ?? '${index + 1}'),
        description: remarkNote.isNotEmpty
            ? remarkNote
            : _describeTransport(transport, map),
        flag: '${map['serverFlag'] ?? ''}'.trim(),
        address: endpoint.$1,
        port: endpoint.$2,
        config: config,
      ),
    );
  }
  return servers;
}

/// The address and port of the outbound that carries traffic.
///
/// Xray states them per protocol: `settings.vnext[0]` for vless/vmess, `settings.servers[0]`
/// for trojan, `settings.address`/`port` at the top for the shims. Anything else yields
/// `('', 0)`, which the row shows as "—" instead of inventing a value.
(String, int) _endpointOf(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return ('', 0);
  const routers = {'freedom', 'blackhole', 'dns', 'selector', 'urltest', 'fallback'};
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}'.toLowerCase();
    if (protocol.isEmpty || routers.contains(protocol)) continue;
    final settings = item['settings'];
    if (settings is! Map) continue;
    final vnext = settings['vnext'];
    if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
      final first = vnext.first as Map;
      return ('${first['address'] ?? ''}'.trim(), _port(first['port']));
    }
    final servers = settings['servers'];
    if (servers is List && servers.isNotEmpty && servers.first is Map) {
      final first = servers.first as Map;
      return ('${first['address'] ?? ''}'.trim(), _port(first['port']));
    }
    final direct = '${settings['address'] ?? ''}'.trim();
    if (direct.isNotEmpty) return (direct, _port(settings['port']));
  }
  return ('', 0);
}

int _port(Object? value) {
  if (value is int) return value;
  return int.tryParse('${value ?? ''}') ?? 0;
}

/// A full configuration carries both halves of the tunnel, per the format's own definition.
bool _isFullConfig(Map item) =>
    item['inbounds'] != null || item['outbounds'] != null;

/// The tag of the first outbound that carries traffic.
///
/// Per the docs the server's name is the first proxy outbound — not the first outbound,
/// which is usually `direct` or a balancer selector.
String? _firstProxyTag(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return null;
  const routers = {'freedom', 'blackhole', 'dns', 'selector', 'urltest', 'fallback'};
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}'.toLowerCase();
    final tag = '${item['tag'] ?? ''}'.trim();
    if (tag.isEmpty) continue;
    if (routers.contains(protocol)) continue;
    return tag;
  }
  return null;
}

/// The server the owner means, by name; the first one when the name is unknown.
///
/// A selection made for the engine's list does not survive here (the two builds name their
/// servers differently), so an unknown name must not leave the portal without a node.
XrayServerConfig? xrayServerFor(List<XrayServerConfig> servers, String? preferred) {
  if (servers.isEmpty) return null;
  if (preferred != null) {
    for (final server in servers) {
      if (server.name == preferred) return server;
    }
  }
  return servers.first;
}

/// The protocol of the outbound that carries traffic.
String _protocolOf(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return 'xray';
  const routers = {'freedom', 'blackhole', 'dns', 'selector', 'urltest', 'fallback'};
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}'.toLowerCase();
    if (protocol.isEmpty || routers.contains(protocol)) continue;
    return protocol;
  }
  return 'xray';
}

/// The transport, which is what distinguishes two servers of the same protocol.
String? _transportOf(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return null;
  for (final item in outbounds) {
    if (item is! Map) continue;
    final stream = item['streamSettings'];
    if (stream is! Map) continue;
    final network = '${stream['network'] ?? ''}'.trim();
    if (network.isNotEmpty && network != 'tcp') return network;
    return null;
  }
  return null;
}

/// The description when the panel gave none: the transport, else nothing.
String _describeTransport(String? transport, Map meta) {
  final stated = '${meta['serverDescription'] ?? ''}'.trim();
  if (stated.isNotEmpty) return stated;
  return transport == null ? '' : transport.toUpperCase();
}
