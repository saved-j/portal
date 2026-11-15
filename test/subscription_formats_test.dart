import 'dart:convert';

import 'package:fl_clash/core/subscription_formats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clash yaml is recognised by its proxies list', () {
    expect(
      detectFormat('proxies:\n  - name: a\n    type: vless\nproxy-groups: []\nrules: []\n'),
      SubscriptionFormat.mihomo,
    );
  });

  test('plain share links are recognised as the xray format', () {
    expect(
      detectFormat('vless://uuid@host:443?type=ws#node\nvmess://abc\n'),
      SubscriptionFormat.xray,
    );
  });

  test('base64 share links are decoded before deciding', () {
    final inner = 'vless://uuid@host:443?type=ws#node\ntrojan://pass@host:443#n2\n';
    final encoded = base64Encode(utf8.encode(inner));
    expect(detectFormat(encoded), SubscriptionFormat.xray);
  });

  test('an error page is not a subscription, however green the light would look', () {
    expect(detectFormat('Подписка временно недоступна'), isNull);
    expect(detectFormat('<html><body>502 Bad Gateway</body></html>'), isNull);
    expect(detectFormat('{"error":"not found"}'), isNull);
    expect(detectFormat(''), isNull);
  });

  test('a port-only clash config still counts as the engine format', () {
    expect(detectFormat('port: 7890\nmode: rule\n'), SubscriptionFormat.mihomo);
  });

  test('each format asks with its own user-agent', () {
    expect(subscriptionUserAgents[SubscriptionFormat.mihomo], contains('mihomo'));
    expect(subscriptionUserAgents[SubscriptionFormat.xray], isNot(contains('mihomo')));
  });
}
