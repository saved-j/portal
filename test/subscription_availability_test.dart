import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/core/subscription_availability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a vless reality link becomes a node the engine could run', () {
    final nodes = parseShareLinks(
      'vless://11111111-2222-3333-4444-555555555555@a.example.net:443'
      '?type=tcp&security=reality&pbk=PUB&sid=ab12&sni=www.microsoft.com&fp=chrome'
      '#EE-1',
    );
    expect(nodes, hasLength(1));
    final node = nodes.first;
    expect(node['name'], 'EE-1');
    expect(node['server'], 'a.example.net');
    expect(node['port'], 443);
    expect(node['uuid'], '11111111-2222-3333-4444-555555555555');
    expect(node['reality-opts'], {'public-key': 'PUB', 'short-id': 'ab12'});
    expect(node['servername'], 'www.microsoft.com');
  });

  test('a vless ws link keeps its path and host header', () {
    final nodes = parseShareLinks(
      'vless://uuid@b.example.net:443?type=ws&security=tls&path=%2Fray&host=cdn.example.net#WS',
    );
    final node = nodes.single;
    expect(node['network'], 'ws');
    expect(node['ws-path'], '/ray');
    expect(node['ws-headers'], {'Host': 'cdn.example.net'});
    expect(node['tls'], true);
  });

  test('a base64-wrapped list is unwrapped before parsing', () {
    final inner = 'trojan://pass@c.example.net:443?sni=c.example.net#T1\n';
    final wrapped = base64Encode(utf8.encode(inner));
    final nodes = parseShareLinks(wrapped);
    expect(nodes, hasLength(1));
    expect(nodes.first['type'], 'trojan');
    expect(nodes.first['password'], 'pass');
  });

  test('a vmess link is read from its base64 json', () {
    final payload = base64Encode(utf8.encode(jsonEncode({
      'ps': 'VM',
      'add': 'd.example.net',
      'port': '443',
      'id': 'uuid-1',
      'aid': '0',
      'net': 'ws',
      'tls': 'tls',
      'sni': 'd.example.net',
      'path': '/v',
      'host': 'd.example.net',
    })));
    final nodes = parseShareLinks('vmess://$payload');
    expect(nodes, hasLength(1));
    expect(nodes.first['name'], 'VM');
    expect(nodes.first['network'], 'ws');
    expect(nodes.first['tls'], true);
  });

  test('garbage in the body yields no nodes rather than a broken one', () {
    expect(parseShareLinks('<html>502</html>'), isEmpty);
    expect(parseShareLinks('vless://'), isEmpty);
    expect(parseShareLinks(''), isEmpty);
  });

  test('the selection falls back to the first node when the name is unknown', () {
    final nodes = parseShareLinks(
      'vless://u@a:443#Node-A\nvless://u@b:443#Node-B\n',
    );
    expect(xrayNodeFor(nodes, 'Node-B')?['name'], 'Node-B');
    expect(xrayNodeFor(nodes, 'Missing')?['name'], 'Node-A');
    expect(xrayNodeFor(const [], 'x'), isNull);
  });

  test('availability reports each format separately', () {
    final onlyXray = SubscriptionAvailability(
      xray: Uint8List.fromList(utf8.encode('vless://u@a:443#n')),
    );
    expect(onlyXray.hasXray, isTrue);
    expect(onlyXray.hasMihomo, isFalse);
    expect(usableForXray(onlyXray), isTrue);
    expect(usableForEngine(onlyXray), isFalse);
  });
}
