import 'dart:convert';

import 'package:fl_clash/core/subscription_formats.dart';
import 'package:fl_clash/core/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Happ and Incy are served a ready Xray document instead of a link list, so the app must
/// recognise it and put its socks inbound where the engine expects it.
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
    final config = jsonDecode(withSocksInbound(wrapped)) as Map<String, dynamic>;
    expect((config['inbounds'] as List).first['port'], 10808);
    expect(config['inbounds'], isA<List>());
    expect(jsonDecode(withSocksInbound(wrapped)), isA<Map>(),
        reason: 'the wrapper is unwrapped for the core');
  });

  test('a json document without inbounds or outbounds is not', () {
    expect(detectFormat('{"hasMihomo": true}'), isNull);
  });

  test('the socks inbound is moved to the port the engine forwards to', () {
    final result = withSocksInbound(panelConfig, port: 10808);
    final config = jsonDecode(result) as Map<String, dynamic>;
    final inbounds = config['inbounds'] as List;
    expect(inbounds, hasLength(1), reason: 'the old socks inbound is replaced');
    expect((inbounds.first as Map)['port'], 10808);
    expect((inbounds.first as Map)['listen'], '127.0.0.1');
    // everything else survives, which is the point of passing the document through
    expect((config['outbounds'] as List), hasLength(1));
  });

  test('a config with no socks inbound gets one, in front of the others', () {
    const noSocks = '{"inbounds": [{"port": 9000, "protocol": "http"}], "outbounds": []}';
    final config = jsonDecode(withSocksInbound(noSocks)) as Map<String, dynamic>;
    final inbounds = config['inbounds'] as List;
    expect(inbounds, hasLength(2));
    expect((inbounds.first as Map)['protocol'], 'socks');
    expect((inbounds.last as Map)['protocol'], 'http');
  });
}
