/// One subscription link, several formats.
///
/// A panel may answer the same URL differently depending on the client that asks: a
/// mihomo user-agent gets Clash YAML, an Xray user-agent gets a share-link list. The app
/// needs both, because the engine runs mihomo and the second core runs Xray, and the
/// owner must be able to see which of the two a link actually offers.
library;

import 'dart:convert';

/// A subscription link and the format each client gets from it.
enum SubscriptionFormat {
  /// Clash / mihomo YAML: proxies, proxy-groups and the routing rules.
  mihomo,

  /// A list of share links (vless://, vmess://, trojan://) in plain text or base64.
  xray,
}

/// The user-agent that asks for each format.
///
/// These are the strings panels recognise most often; a panel that ignores them answers
/// with whatever it defaults to, and [detectFormat] is what decides whether the answer is
/// usable rather than trusting the request.
const subscriptionUserAgents = <SubscriptionFormat, String>{
  SubscriptionFormat.mihomo: 'mihomo/1.19.34',
  SubscriptionFormat.xray: 'Happ/2.9.1',
};

/// Clients to imitate, in the order they are tried.
///
/// A panel serves the node list only to the clients it knows, and answers `502` to the
/// rest — so which name works is the panel's decision, not ours. Asking as the popular
/// ones in turn is the only reliable way to find out without the panel's API.
const xrayUserAgentCandidates = <String>[
  // Incy first: the panel recognises its current version and answers with the named JSON
  // subscription. Both clients are accepted; the first body that parses wins.
  'Incy/3.9.9',
  'Incy/2.0.0',
  'Happ/3.9.9',
  'Happ/2.9.1',
  'v2rayTun/1.6.0',
  'v2rayNG/1.8.5',
  'Streisand/1.0',
  'Karing/1.1.0',
  'v2rayN/6.31',
  'sing-box/1.10.0',
];

/// What one download attempt produced.
class SubscriptionAttempt {
  const SubscriptionAttempt({
    required this.format,
    required this.ok,
    required this.body,
    this.reason = '',
  });

  final SubscriptionFormat format;
  final bool ok;
  final String body;

  /// Why an attempt was rejected, for a log or a support question; empty when ok.
  final String reason;
}

/// Decides which format a body actually is, from the body alone.
///
/// A 200 with an error page must not count as a subscription: the caller shows a green
/// light per format, and a light that lies is worse than no light.
SubscriptionFormat? detectFormat(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;

  // A client config rather than a link list: Happ and Incy are served a JSON document with
  // inbounds/outbounds, which is Xray's own shape and what the second core runs directly.
  // It arrives either as an object or wrapped in a one-element array, so both are read.
  if (text.startsWith('{') || text.startsWith('[')) {
    final json = _tryDecodeJson(text);
    if (_looksLikeClientConfig(json)) return SubscriptionFormat.xray;
  }

  // An Xray client config served under a *client* name. The panel decides by user-agent, and
  // some panels keep serving the Happ/Incy answer to the mihomo name as well — a body full of
  // outbounds is not Clash YAML however it arrived, and reading it as a format this mode can
  // use would let it replace a working config with a document the engine cannot run.
  if (_looksLikeClientConfig(_tryDecodeJson(text))) return SubscriptionFormat.xray;

  // Clash YAML: a mapping with a proxies list, the one thing the engine cannot run without.
  if (RegExp(r'^proxies\s*:', multiLine: true).hasMatch(text)) {
    return SubscriptionFormat.mihomo;
  }
  if (text.contains('proxy-groups:') && text.contains('proxies:')) {
    return SubscriptionFormat.mihomo;
  }

  // Share links, either plain or wrapped in base64 as most panels ship them.
  final decoded = _maybeBase64(text);
  for (final source in [text, decoded]) {
    if (source == null) continue;
    if (RegExp(r'^(vless|vmess|trojan|ss|hysteria2?|tuic)://', multiLine: true)
        .hasMatch(source)) {
      return SubscriptionFormat.xray;
    }
  }

  // A Clash config that only has groups and no proxies is still YAML the engine reads.
  if (text.startsWith('port:') || text.startsWith('mixed-port:')) {
    return SubscriptionFormat.mihomo;
  }
  return null;
}

String? _maybeBase64(String text) {
  final compact = text.replaceAll(RegExp(r'\s'), '');
  if (compact.length < 20) return null;
  if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) return null;
  try {
    return String.fromCharCodes(base64Decode(base64Url.normalize(compact)));
  } catch (_) {
    return null;
  }
}

Object? _tryDecodeJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// True when the body is an Xray *client config* — outbounds and settings, not a link list.
///
/// The distinction is load-bearing: a link list is what any core can run after one conversion,
/// while a client config belongs to the core it was written for. Turning the second into the
/// first moved the second core's servers into the engine's list, which the owner rejects.
bool isClientConfig(String body) =>
    _looksLikeClientConfig(_tryDecodeJson(body.trim()));

/// True for an Xray-shaped document, either bare or wrapped in a list.
bool _looksLikeClientConfig(Object? json) {
  bool isConfig(Object? value) =>
      value is Map && (value['outbounds'] != null || value['inbounds'] != null);
  if (isConfig(json)) return true;
  if (json is List) return json.any(isConfig);
  return false;
}

/// The config inside a body that may be wrapped in a one-element array.
Map<String, dynamic>? clientConfigOf(Object? json) {
  if (json is Map && (json['outbounds'] != null || json['inbounds'] != null)) {
    return Map<String, dynamic>.from(json);
  }
  if (json is List) {
    for (final item in json) {
      if (item is Map && (item['outbounds'] != null || item['inbounds'] != null)) {
        return Map<String, dynamic>.from(item);
      }
    }
  }
  return null;
}

/// Decodes a subscription body into a client config, or null when it is not one.
Map<String, dynamic>? decodeClientConfig(String body) =>
    clientConfigOf(_tryDecodeJson(body));
