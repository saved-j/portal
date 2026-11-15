/// Turns one Clash/Mihomo proxy entry into an Xray configuration.
///
/// The app speaks Clash YAML: a subscription is a list of proxies with a `type` and a few
/// protocol fields. Xray speaks its own JSON. This file is the only place that knows both,
/// so the whole X-Ray path can be tested without a phone, a tunnel or a panel.
library;

import 'dart:convert';

/// A single outbound in Xray's JSON shape, plus the socks inbound the app uses.
Map<String, dynamic> xrayConfigFor(
  Map<String, dynamic> proxy, {
  int socksPort = 10808,
  String logLevel = 'warning',
}) {
  final type = (proxy['type'] as String? ?? '').toLowerCase();
  final outbound = switch (type) {
    'vless' => _vless(proxy),
    'vmess' => _vmess(proxy),
    'trojan' => _trojan(proxy),
    _ => throw UnsupportedProxyType(type),
  };
  return {
    'log': {'loglevel': logLevel},
    'inbounds': [
      {
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'port': socksPort,
        'protocol': 'socks',
        'settings': {'udp': false},
      },
    ],
    'outbounds': [
      outbound,
      {'tag': 'blocked', 'protocol': 'blackhole'},
    ],
  };
}

class UnsupportedProxyType implements Exception {
  const UnsupportedProxyType(this.type);
  final String type;

  @override
  String toString() => 'UnsupportedProxyType($type)';
}

Map<String, dynamic> _vless(Map<String, dynamic> proxy) {
  final settings = <String, dynamic>{
    'vnext': [
      {
        'address': proxy['server'],
        'port': _port(proxy),
        'users': [
          {
            'id': proxy['uuid'],
            'encryption': (proxy['encryption'] as String?) ?? 'none',
            if (proxy['flow'] != null) 'flow': proxy['flow'],
          },
        ],
      },
    ],
  };

  final stream = _stream(proxy);
  return {
    'tag': 'proxy',
    'protocol': 'vless',
    'settings': settings,
    'streamSettings': stream,
  };
}

Map<String, dynamic> _vmess(Map<String, dynamic> proxy) {
  return {
    'tag': 'proxy',
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': proxy['server'],
          'port': _port(proxy),
          'users': [
            {
              'id': proxy['uuid'],
              'alterId': proxy['alterId'] ?? 0,
              'security': (proxy['cipher'] as String?) ?? 'auto',
            },
          ],
        },
      ],
    },
    'streamSettings': _stream(proxy),
  };
}

Map<String, dynamic> _trojan(Map<String, dynamic> proxy) {
  return {
    'tag': 'proxy',
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {
          'address': proxy['server'],
          'port': _port(proxy),
          'password': proxy['password'],
        },
      ],
    },
    'streamSettings': _stream(proxy),
  };
}

int _port(Map<String, dynamic> proxy) {
  final raw = proxy['port'];
  if (raw is int) return raw;
  final parsed = int.tryParse('$raw');
  if (parsed == null) throw const FormatException('proxy has no usable port');
  return parsed;
}

/// Transport, TLS and REALITY. Clash keeps these flat on the proxy entry and Xray wants
/// them nested, which is the whole reason this conversion cannot be a rename.
Map<String, dynamic> _stream(Map<String, dynamic> proxy) {
  final network = (proxy['network'] as String?) ?? 'tcp';
  final stream = <String, dynamic>{'network': network};

  switch (network) {
    case 'ws':
      stream['wsSettings'] = {
        'path': proxy['ws-path'] ?? proxy['wsPath'] ?? '/',
        if (proxy['ws-headers'] != null || proxy['wsHeaders'] != null)
          'headers': proxy['ws-headers'] ?? proxy['wsHeaders'],
      };
      break;
    case 'grpc':
      stream['grpcSettings'] = {
        'serviceName': proxy['grpc-service-name'] ?? proxy['grpcServiceName'] ?? '',
        if (proxy['grpc-mode'] != null) 'multiMode': proxy['grpc-mode'] == 'multi',
      };
      break;
    case 'h2':
      stream['httpSettings'] = {
        'path': proxy['h2-path'] ?? proxy['h2Path'] ?? '/',
        'host': [proxy['h2-host'] ?? proxy['h2Host'] ?? proxy['server']],
      };
      break;
  }

  final reality = proxy['reality-opts'] ?? proxy['realityOpts'];
  final tls = proxy['tls'];
  if (reality is Map) {
    stream['security'] = 'reality';
    stream['realitySettings'] = {
      'serverName': reality['server-name'] ?? reality['serverName'] ?? proxy['servername'],
      'fingerprint': proxy['client-fingerprint'] ?? 'chrome',
      'publicKey': reality['public-key'] ?? reality['publicKey'],
      'shortId': reality['short-id'] ?? reality['shortId'] ?? '',
    };
  } else if (tls == true) {
    stream['security'] = 'tls';
    stream['tlsSettings'] = {
      'serverName': proxy['servername'] ?? proxy['sni'] ?? proxy['server'],
      'allowInsecure': proxy['skip-cert-verify'] ?? false,
      if (proxy['alpn'] != null) 'alpn': proxy['alpn'],
      if (proxy['client-fingerprint'] != null)
        'fingerprint': proxy['client-fingerprint'],
    };
  }

  return stream;
}

/// JSON text, ready to be written next to the binary.
String xrayConfigJson(Map<String, dynamic> proxy, {int socksPort = 10808}) =>
    const JsonEncoder.withIndent('  ').convert(
      xrayConfigFor(proxy, socksPort: socksPort),
    );
