import 'dart:convert';

import 'package:fl_clash/core/subscription_formats.dart';
import 'package:flutter_test/flutter_test.dart';

/// Happ and Incy are served a ready Xray document instead of a link list, so the app must
/// recognise it and hand the document itself to the child, whose entry point is the tunnel.
void main() {
  const panelConfig = '''
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"tag": "old", "listen": "127.0.0.1", "port": 2080, "protocol": "socks"}],
  "outbounds": [{"tag": "proxy", "protocol": "vless", "settings": {}}]
}
''';

  test('a json config is recognised as the xray format', () {
    expect(detectFormat(panelConfig), SubscriptionFormat.xray);
  });

  test('a config wrapped in a one-element array is still a config', () {
    final wrapped = '[$panelConfig]';
    expect(detectFormat(wrapped), SubscriptionFormat.xray);
    final document = decodeClientConfig(wrapped);
    expect(document, isA<Map>(), reason: 'the wrapper is unwrapped for the child');
    expect(document!['outbounds'], isA<List>());
  });

  test('a json document without inbounds or outbounds is not', () {
    expect(detectFormat('{"hasMihomo": true}'), isNull);
  });

  test('the document reaches the child as the panel wrote it', () {
    final document = decodeClientConfig(panelConfig);
    expect(document, isNotNull);
    // Nothing rewrites the inbounds any more: the plugin replaces them with the tunnel.
    final inbounds = document!['inbounds'] as List;
    expect(inbounds, hasLength(1));
    expect((inbounds.first as Map)['port'], 2080);
    expect((document['outbounds'] as List), hasLength(1));
    expect(jsonDecode(panelConfig)['log'], document['log']);
  });
}
