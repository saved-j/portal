/// The document the simple portal actually runs: every node of the subscription, one selected.
///
/// The child used to be started on the selected node alone, which made the core blind to the
/// rest of the list: it holds one outbound, so there is nothing to measure and every figure had
/// to be produced by the app — a second core, a sweep, a map of its own. mihomo has never worked
/// that way. It holds every node of a group and its own url-test keeps the numbers fresh, which
/// is why a dashboard can show them live without measuring anything.
///
/// This document gives the child the same shape: one outbound per node, a routing rule that
/// sends the tunnel's traffic to the selected one, and a `burstObservatory` that makes the core
/// time all of them on its own schedule. The app then reads the numbers instead of producing
/// them.
library;

import 'dart:convert';

import 'xray_subscription.dart';

/// The tag prefix every node's outbound carries. The observatory selects by it.
const portalNodeTagPrefix = 'node:';

/// The outbound the selected node's traffic goes to before the core starts.
const portalSelectedTag = 'portal-selected';

/// The document for [servers] with [selected] as the node the tunnel uses.
///
/// The panel's own element is passed through per node: its first real outbound is the node, and
/// anything it declares about that node (transport, tls, headers) is kept untouched. What the
/// document adds is a tag, a rule, and the observatory.
///
/// [probeInterval] is how often the core re-times every node. mihomo's own url-test groups use
/// the same order of magnitude; the value comes from the owner's switch, not from a constant
/// buried here.
String portalChildDocument(
  List<XrayServerConfig> servers, {
  required String selected,
  Duration probeInterval = const Duration(seconds: 60),
  String probeUrl = 'https://www.gstatic.com/generate_204',
}) {
  final outbounds = <Map<String, Object?>>[];
  final seen = <String, int>{};
  for (var index = 0; index < servers.length; index++) {
    final server = servers[index];
    final node = _nodeOutbound(server.config);
    if (node == null) continue;
    // The tag carries the name, not the position. Two lists of the same subscription can
    // differ in order — one has the auto-select group, the other does not — and a tag that
    // means "the third node" then names the wrong row. The name is the only thing both
    // sides agree on, so it is what the tag says.
    final repeat = seen.update(server.name, (count) => count + 1, ifAbsent: () => 0);
    final tag = repeat == 0
        ? '$portalNodeTagPrefix${server.name}'
        : '$portalNodeTagPrefix${server.name}#$repeat';
    outbounds.add({...node, 'tag': tag});
    if (server.name == selected) {
      // The selected node keeps a second handle with a stable tag, so the routing rule below
      // does not have to name an index that changes when the subscription is re-read.
      outbounds.add({...node, 'tag': portalSelectedTag});
    }
  }
  // A selected name that is not in the list (a stale pick) falls back to the first node: the
  // portal must come up on something rather than refuse.
  if (!outbounds.any((item) => item['tag'] == portalSelectedTag) && outbounds.isNotEmpty) {
    final first = outbounds.first;
    outbounds.add({...first, 'tag': portalSelectedTag});
  }
  outbounds.add({'tag': 'portal-direct', 'protocol': 'freedom'});
  outbounds.add({'tag': 'portal-blocked', 'protocol': 'blackhole'});

  return const JsonEncoder.withIndent(' ').convert({
    'log': {'loglevel': 'warning'},
    'outbounds': outbounds,
    // The tunnel's traffic goes to the node the owner picked; the observatory does the rest.
    'routing': {
      'domainStrategy': 'AsIs',
      'rules': [
        {
          'type': 'field',
          'network': 'tcp,udp',
          'outboundTag': portalSelectedTag,
        },
      ],
    },
    // The core times every node itself, on this period, and keeps the results. Nothing of the
    // app runs for this: no sweep, no second core, no map to fill.
    'burstObservatory': {
      'subjectSelector': [portalNodeTagPrefix],
      // Interval and timeout are Go duration strings, not numbers: Xray parses them with
      // time.ParseDuration and rejects anything else.
      'pingConfig': {
        'destination': probeUrl,
        'interval': '${probeInterval.inSeconds}s',
        'timeout': '5s',
        'sampling': 3,
        'httpMethod': 'HEAD',
      },
    },
  });
}

/// The name [tag] belongs to in a document built by [portalChildDocument], or null.
///
/// The order of the tag indexes is the order of the subscription, so the list the app keeps and
/// the list the core runs name the same nodes — this is the one place that mapping is written.
String? portalNameForTag(List<XrayServerConfig> servers, String tag) {
  final name = portalNameOfTag(tag);
  if (name == null) return null;
  // Checked against the list rather than trusted: a tag from a document built on an older
  // subscription must not put its figure on a row of the newer one.
  for (final server in servers) {
    if (server.name == name) return name;
  }
  return null;
}

/// The name a tag carries, with no list to check it against.
String? portalNameOfTag(String tag) {
  if (!tag.startsWith(portalNodeTagPrefix)) return null;
  var name = tag.substring(portalNodeTagPrefix.length);
  final repeat = name.lastIndexOf('#');
  if (repeat > 0) {
    final suffix = name.substring(repeat + 1);
    if (int.tryParse(suffix) != null) name = name.substring(0, repeat);
  }
  return name.isEmpty ? null : name;
}

/// The tag of the first node called [name] in a document built by [portalChildDocument].
String? portalTagOf(List<XrayServerConfig> servers, String name) {
  for (final server in servers) {
    if (server.name == name) return '$portalNodeTagPrefix$name';
  }
  return null;
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
    if (protocol.isEmpty || protocol == 'blackhole' || protocol == 'freedom') continue;
    if (item.containsKey('balancers') || item.containsKey('selector')) continue;
    return Map<String, Object?>.from(item);
  }
  return null;
}
