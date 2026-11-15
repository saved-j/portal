/// Wraps the engine's own configuration so that all traffic leaves through Xray.
///
/// The app keeps mihomo for TUN, DNS and the rule engine. When the owner turns the
/// "Сеть порталов" switch off, the simple mode must not route through the subscription's
/// own outbounds — it must hand everything to a local Xray that owns the real node.
///
/// That is done by adding one socks5 proxy pointing at 127.0.0.1 and forcing global mode.
/// This file is the whole of that decision, so it can be tested without a tunnel.
library;

const xrayBridgeTag = 'portal-xray';
const xrayBridgeGroup = 'PORTAL-XRAY';
const xrayDefaultPort = 10808;

/// Returns a copy of [config] in which every connection goes to the local Xray.
///
/// The original map is not modified: switching back must be possible by simply dropping
/// the returned copy.
Map<String, dynamic> withXrayBridge(
  Map<String, dynamic> config, {
  int port = xrayDefaultPort,
}) {
  final out = <String, dynamic>{...config};

  final proxies = <dynamic>[
    ...?(config['proxies'] as List?)?.where(
      (p) => p is Map && p['name'] != xrayBridgeTag,
    ),
    {
      'name': xrayBridgeTag,
      'type': 'socks5',
      'server': '127.0.0.1',
      'port': port,
      'udp': false,
      'skip-cert-verify': true,
    },
  ];
  out['proxies'] = proxies;

  final groups = <dynamic>[
    ...?(config['proxy-groups'] as List?)?.where(
      (g) => g is Map && g['name'] != xrayBridgeGroup,
    ),
    {
      'name': xrayBridgeGroup,
      'type': 'select',
      'proxies': [xrayBridgeTag],
    },
  ];
  out['proxy-groups'] = groups;

  // Global mode plus this one group is what makes the engine a plain pipe: no rules of
  // its own, nothing selected by delay, everything into Xray.
  out['mode'] = 'global';
  out['GLOBAL'] = xrayBridgeGroup;

  return out;
}

/// True when [config] already carries the bridge, so a second switch-off cannot stack
/// a second socks proxy or a second group on top of the first.
bool hasXrayBridge(Map<String, dynamic> config) {
  final proxies = (config['proxies'] as List?) ?? const [];
  return proxies.any((p) => p is Map && p['name'] == xrayBridgeTag);
}

/// Removes the bridge and restores the mode the config had before it was wrapped.
Map<String, dynamic> withoutXrayBridge(
  Map<String, dynamic> config, {
  String restoreMode = 'rule',
}) {
  final out = <String, dynamic>{...config};
  out['proxies'] = ((config['proxies'] as List?) ?? const [])
      .where((p) => !(p is Map && p['name'] == xrayBridgeTag))
      .toList();
  out['proxy-groups'] = ((config['proxy-groups'] as List?) ?? const [])
      .where((g) => !(g is Map && g['name'] == xrayBridgeGroup))
      .toList();
  if (out['GLOBAL'] == xrayBridgeGroup) {
    out.remove('GLOBAL');
  }
  out['mode'] = restoreMode;
  return out;
}
