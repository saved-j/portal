import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/core/subscription_formats.dart';

/// What a link turned out to offer, as far as the app can tell.
///
/// The panel decides per request, so the answer is never known in advance: it is whatever
/// came back when we asked with each client's user-agent.
class SubscriptionAvailability {
  const SubscriptionAvailability({
    this.mihomo,
    this.xray,
    this.notes = const [],
  });

  /// The Clash YAML body, when the panel served one.
  final Uint8List? mihomo;

  /// The share-link body, when the panel served one.
  final Uint8List? xray;

  /// One line per attempt that failed, so a grey light can say why.
  final List<String> notes;

  bool get hasMihomo => mihomo != null;
  bool get hasXray => xray != null;

  /// The node list decoded from the xray body, ready for the converter.
  List<Map<String, dynamic>> get xrayNodes =>
      xray == null ? const [] : parseShareLinks(utf8.decode(xray!, allowMalformed: true));

  SubscriptionAvailability withXray(Uint8List? body) =>
      SubscriptionAvailability(mihomo: mihomo, xray: body, notes: notes);

  SubscriptionAvailability withMihomo(Uint8List? body) =>
      SubscriptionAvailability(mihomo: body, xray: xray, notes: notes);

  Map<String, dynamic> toJson() => {
        'hasMihomo': hasMihomo,
        'hasXray': hasXray,
        'notes': notes,
      };
}

/// Reads a list of share links into proxy definitions the engine can hold.
///
/// Only the fields the panel actually put in the link are filled; anything else is the
/// engine's default, which keeps this function honest about what it was told.
List<Map<String, dynamic>> parseShareLinks(String body) {
  final decoded = _unwrapBase64(body);
  final nodes = <Map<String, dynamic>>[];
  for (final line in decoded.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (text.isEmpty) continue;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) continue;
    final node = switch (uri.scheme) {
      'vless' => _vlessFromUri(uri, text),
      'trojan' => _trojanFromUri(uri, text),
      'vmess' => _vmessFromLink(text),
      _ => null,
    };
    if (node != null) nodes.add(node);
  }
  return nodes;
}

String _unwrapBase64(String body) {
  final text = body.trim();
  if (text.contains('://')) return text;
  try {
    return utf8.decode(base64Decode(base64Url.normalize(text.replaceAll(RegExp(r'\s'), ''))));
  } catch (_) {
    return text;
  }
}

String _labelOf(Uri uri, String fallback) {
  final hash = uri.fragment.trim();
  return hash.isEmpty ? fallback : Uri.decodeComponent(hash);
}

Map<String, dynamic>? _vlessFromUri(Uri uri, String raw) {
  final uuid = uri.userInfo;
  if (uuid.isEmpty || uri.host.isEmpty) return null;
  final query = uri.queryParameters;
  final node = <String, dynamic>{
    'name': _labelOf(uri, '${uri.host}:${uri.port}'),
    'type': 'vless',
    'server': uri.host,
    'port': uri.port == 0 ? 443 : uri.port,
    'uuid': uuid,
    'network': query['type'] ?? 'tcp',
    'udp': true,
  };
  if ((query['security'] ?? '') == 'tls') node['tls'] = true;
  if ((query['security'] ?? '') == 'reality') {
    node['tls'] = true;
    node['reality-opts'] = {
      'public-key': query['pbk'] ?? '',
      'short-id': query['sid'] ?? '',
    };
  }
  if (query['sni'] != null) node['servername'] = query['sni'];
  if (query['fp'] != null) node['client-fingerprint'] = query['fp'];
  if (query['flow'] != null && query['flow']!.isNotEmpty) node['flow'] = query['flow'];
  if (query['path'] != null && query['path']!.isNotEmpty) node['ws-path'] = query['path'];
  if (query['host'] != null && query['host']!.isNotEmpty) {
    node['ws-headers'] = {'Host': query['host']};
  }
  if (query['serviceName'] != null) node['grpc-service-name'] = query['serviceName'];
  return node;
}

Map<String, dynamic>? _trojanFromUri(Uri uri, String raw) {
  if (uri.userInfo.isEmpty || uri.host.isEmpty) return null;
  final query = uri.queryParameters;
  final node = <String, dynamic>{
    'name': _labelOf(uri, '${uri.host}:${uri.port}'),
    'type': 'trojan',
    'server': uri.host,
    'port': uri.port == 0 ? 443 : uri.port,
    'password': uri.userInfo,
    'network': query['type'] ?? 'tcp',
    'udp': true,
    'skip-cert-verify': query['allowInsecure'] == '1',
  };
  if (query['sni'] != null) node['servername'] = query['sni'];
  if (query['path'] != null) node['ws-path'] = query['path'];
  if (query['host'] != null) node['ws-headers'] = {'Host': query['host']};
  return node;
}

/// vmess links are a base64 JSON blob rather than a URI with a query.
Map<String, dynamic>? _vmessFromLink(String raw) {
  final payload = raw.substring('vmess://'.length).trim();
  try {
    final json = jsonDecode(utf8.decode(base64Decode(base64Url.normalize(payload))));
    if (json is! Map) return null;
    final server = '${json['add'] ?? ''}';
    final uuid = '${json['id'] ?? ''}';
    if (server.isEmpty || uuid.isEmpty) return null;
    final tls = '${json['tls'] ?? ''}';
    final node = <String, dynamic>{
      'name': '${json['ps'] ?? '$server:${json['port']}'}',
      'type': 'vmess',
      'server': server,
      'port': int.tryParse('${json['port']}') ?? 443,
      'uuid': uuid,
      'alterId': int.tryParse('${json['aid']}') ?? 0,
      'cipher': '${json['scy'] ?? 'auto'}',
      'network': '${json['net'] ?? 'tcp'}',
      'udp': true,
    };
    if (tls == 'tls') node['tls'] = true;
    if ('${json['sni'] ?? ''}'.isNotEmpty) node['servername'] = '${json['sni']}';
    if ('${json['path'] ?? ''}'.isNotEmpty) node['ws-path'] = '${json['path']}';
    if ('${json['host'] ?? ''}'.isNotEmpty) {
      node['ws-headers'] = {'Host': '${json['host']}'};
    }
    return node;
  } catch (_) {
    return null;
  }
}

/// Picks the node the owner means from the xray list.
///
/// The names come from the link fragments and rarely match the engine's names, so a
/// selection made for the engine is honoured when it exists and the first node is used
/// otherwise — better a working portal than none, and the strip shows which node it is.
Map<String, dynamic>? xrayNodeFor(
  List<Map<String, dynamic>> nodes,
  String? preferred,
) {
  if (nodes.isEmpty) return null;
  if (preferred != null) {
    for (final node in nodes) {
      if (node['name'] == preferred) return node;
    }
  }
  return nodes.first;
}

/// True when the link answered with a body the engine can run.
bool usableForEngine(SubscriptionAvailability availability) =>
    availability.hasMihomo;

/// True when the link answered with nodes the second core can run.
bool usableForXray(SubscriptionAvailability availability) =>
    availability.xrayNodes.isNotEmpty;

/// Kept for callers that only need the format names.
List<SubscriptionFormat> formatsOf(SubscriptionAvailability availability) => [
      if (availability.hasMihomo) SubscriptionFormat.mihomo,
      if (availability.hasXray) SubscriptionFormat.xray,
    ];

/// The nodes a ready Xray config actually offers, as engine-shaped proxies.
///
/// Happ and Incy get a compiled config, not a link list, so the owner's server list must be
/// rebuilt from it: the selectors, the nodes and the group that holds them. Without this the
/// list keeps showing the engine's servers after the switch has already moved the traffic.
List<Map<String, dynamic>> xrayConfigServers(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return const [];

  /// Tags that carry traffic rather than route it.
  const routers = {'direct', 'block', 'blocked', 'dns', 'dns-out'};
  final nodes = <String, Map<String, dynamic>>{};
  for (final item in outbounds) {
    if (item is! Map) continue;
    final tag = '${item['tag'] ?? ''}';
    final protocol = '${item['protocol'] ?? ''}';
    if (tag.isEmpty) continue;
    if (routers.contains(tag.toLowerCase()) || routers.contains(protocol.toLowerCase())) {
      continue;
    }
    // A selector is a chooser, not a server: it is shown as a group, never as an endpoint.
    if (protocol == 'selector' || protocol == 'urltest' || protocol == 'fallback') continue;
    if (protocol == 'freedom' || protocol == 'blackhole') continue;
    nodes[tag] = proxyShapeFor(item);
  }
  return nodes.values.toList();
}

/// The selector groups inside a ready config, each with the members it may pick.
List<Map<String, dynamic>> xrayConfigGroups(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return const [];
  final groups = <Map<String, dynamic>>[];
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}';
    if (protocol != 'selector' && protocol != 'urltest') continue;
    final tag = '${item['tag'] ?? ''}';
    final members = item['settings'];
    final list = members is Map ? members['servers'] : null;
    groups.add({
      'name': tag,
      'type': protocol == 'urltest' ? 'url-test' : 'select',
      'proxies': [
        if (list is List) for (final member in list) '$member',
      ],
    });
  }
  return groups;
}

/// One outbound as the shape the interface already renders for a server row.
Map<String, dynamic> proxyShapeFor(Map item) {
  final settings = item['settings'];
  final vnext = settings is Map ? settings['vnext'] : null;
  final servers = settings is Map ? settings['servers'] : null;
  String server = '';
  int port = 0;
  if (vnext is List && vnext.isNotEmpty && vnext.first is Map) {
    final first = vnext.first as Map;
    server = '${first['address'] ?? ''}';
    port = int.tryParse('${first['port']}') ?? 0;
  } else if (servers is List && servers.isNotEmpty && servers.first is Map) {
    final first = servers.first as Map;
    server = '${first['address'] ?? ''}';
    port = int.tryParse('${first['port']}') ?? 0;
  }
  final stream = item['streamSettings'];
  final transport = stream is Map ? '${stream['network'] ?? 'tcp'}' : 'tcp';
  return {
    'name': '${item['tag'] ?? ''}',
    'type': '${item['protocol'] ?? 'proxy'}',
    'serverDescription': server.isEmpty ? transport : '$server:$port · $transport',
  };
}
