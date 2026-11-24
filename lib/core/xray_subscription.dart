import 'dart:convert';

import '../common/print.dart';

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
    this.described = false,
    this.flag = '',
    this.address = '',
    this.port = 0,
  });

  final String name;
  final String description;

  /// True when [description] is the panel's own note for this server rather than the fallback
  /// the app derived from the transport.
  ///
  /// The panel puts that note in `meta.serverDescription`, which is the field the clients that
  /// show a comment under the name read. The distinction matters when a body is chosen between
  /// candidates: a list of servers without notes is a poorer answer than the same list with
  /// them, even though it parses the same.
  final bool described;
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

/// Why a body yielded the servers it did, when it yielded none.
enum XraySubscriptionProblem {
  /// Not JSON at all: a panel error page, a truncated answer, or a share-link list.
  notJson,

  /// JSON without a full configuration: the panel spoke another schema.
  noConfig,

  /// A valid answer that carries no servers.
  empty,
}

/// A parsed body: the servers it holds, and why it holds none when it holds none.
///
/// The three empty outcomes used to be one empty list, so a panel answering 502 with an
/// HTML page was indistinguishable from a subscription with no nodes.
class XraySubscriptionResult {
  const XraySubscriptionResult(this.servers, [this.problem, this.error]);

  final List<XrayServerConfig> servers;
  final XraySubscriptionProblem? problem;

  /// The decoder's own words, when there were any.
  final String? error;

  bool get ok => servers.isNotEmpty;

  /// One line a reader can show, naming what the body actually was.
  String get message {
    final reason = switch (problem) {
      null => '',
      XraySubscriptionProblem.notJson => 'the answer is not JSON',
      XraySubscriptionProblem.noConfig => 'no full configuration in the answer',
      XraySubscriptionProblem.empty => 'the subscription is empty',
    };
    if (reason.isEmpty) return '';
    return error == null || error!.isEmpty ? reason : '$reason: $error';
  }
}

/// Reads every server out of a subscription body.
///
/// Kept for the callers that only need the list; [parseXraySubscriptionResult] is what a
/// caller uses when an empty list has to be explained.
List<XrayServerConfig> parseXraySubscription(String body) =>
    parseXraySubscriptionResult(body).servers;

/// Reads every server out of a subscription body, with the reason when there are none.
XraySubscriptionResult parseXraySubscriptionResult(String body) {
  final text = body.trim();
  if (text.isEmpty) {
    return const XraySubscriptionResult([], XraySubscriptionProblem.empty);
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } catch (error) {
    return XraySubscriptionResult(
      const [],
      XraySubscriptionProblem.notJson,
      '$error',
    );
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
  if (configs.isEmpty) {
    return const XraySubscriptionResult([], XraySubscriptionProblem.noConfig);
  }

  // The panel names each configuration in `remarks`; logged once so the shape is visible.
  // Through the app's own printer, which redacts: the remark is the panel's text, and the
  // debug sink this used to write to printed it raw and below the level the log screen shows.
  if (configs.isNotEmpty) {
    final remarks = configs.take(3).map((config) => config['remarks']).join(' | ');
    commonPrint.log('xray remarks: $remarks');
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
    // The panel's own note, in the field the clients that show a comment under the name read:
    // `meta.serverDescription` («Максимальная скорость», «Для мобильного интернета»). A
    // separator inside `remarks` is the other way the same note arrives, so it is the second
    // source rather than the only one.
    final metaNote = '${map['serverDescription'] ?? ''}'.trim();
    final note = metaNote.isNotEmpty ? metaNote : remarkNote;
    final endpoint = _endpointOf(config);
    servers.add(
      XrayServerConfig(
        protocol: _protocolOf(config),
        name: remarkName.isNotEmpty ? remarkName : (_firstProxyTag(config) ?? '${index + 1}'),
        // No invention: a server the panel did not describe has no note, and the row shows
        // its protocol there instead. A transport label is a fact about the connection, not
        // the panel's words about the server.
        description: note,
        described: note.isNotEmpty,
        flag: '${map['serverFlag'] ?? ''}'.trim(),
        address: endpoint.$1,
        port: endpoint.$2,
        config: config,
      ),
    );
  }
  return XraySubscriptionResult(servers);
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

/// The protocol chain of the outbound that carries traffic — `xhttp/tls/vless`,
/// `tls/vless`, `vless`. The badge reads the transport, the security layer when it is not
/// plain, and the protocol, because a single word (`vless`) hid the fact that two servers on
/// the same protocol can run different transports — which is exactly what the owner chooses
/// between. `tcp` is the default transport and is omitted.
String _protocolOf(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List) return 'xray';
  const routers = {'freedom', 'blackhole', 'dns', 'selector', 'urltest', 'fallback'};
  for (final item in outbounds) {
    if (item is! Map) continue;
    final protocol = '${item['protocol'] ?? ''}'.toLowerCase();
    if (protocol.isEmpty || routers.contains(protocol)) continue;
    final stream = item['streamSettings'];
    final network = stream is Map
        ? '${stream['network'] ?? ''}'.trim().toLowerCase()
        : '';
    final security = stream is Map
        ? '${stream['security'] ?? ''}'.trim().toLowerCase()
        : '';
    return [
      if (network.isNotEmpty && network != 'tcp') network,
      if (security.isNotEmpty && security != 'none') security,
      protocol,
    ].join('/');
  }
  return 'xray';
}


