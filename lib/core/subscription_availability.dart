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
