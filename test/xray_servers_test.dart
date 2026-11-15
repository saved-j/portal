import 'dart:convert';

import 'package:fl_clash/core/subscription_availability.dart';
import 'package:flutter_test/flutter_test.dart';

/// The panel's Xray config carries its own servers and selectors. The owner's server list
/// must be rebuilt from it, otherwise the list keeps showing the engine's nodes after the
/// switch has already moved the traffic to the other core.
void main() {
  Map<String, dynamic> config() => jsonDecode('''
{
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"},
    {"tag": "Auto Asia", "protocol": "selector", "settings": {"servers": ["KR-1", "JP-2"]}},
    {"tag": "KR-1", "protocol": "vless",
     "settings": {"vnext": [{"address": "kr.example.net", "port": 443}]},
     "streamSettings": {"network": "tcp"}},
    {"tag": "JP-2", "protocol": "trojan",
     "settings": {"servers": [{"address": "jp.example.net", "port": 8443}]},
     "streamSettings": {"network": "ws"}}
  ]
}
''') as Map<String, dynamic>;

  test('traffic-carrying outbounds become servers, routers do not', () {
    final servers = xrayConfigServers(config());
    final names = servers.map((s) => s['name']).toList();
    expect(names, ['KR-1', 'JP-2']);
    expect(names, isNot(contains('direct')));
    expect(names, isNot(contains('Auto Asia')), reason: 'a selector is a group, not a server');
  });

  test('each server carries the address the row shows', () {
    final servers = xrayConfigServers(config());
    expect(servers.first['serverDescription'], 'kr.example.net:443 · tcp');
    expect(servers.last['serverDescription'], 'jp.example.net:8443 · ws');
  });

  test('a selector becomes a group with its members', () {
    final groups = xrayConfigGroups(config());
    expect(groups, hasLength(1));
    expect(groups.single['name'], 'Auto Asia');
    expect(groups.single['type'], 'select');
    expect((groups.single['proxies'] as List), ['KR-1', 'JP-2']);
  });

  test('the servers a panel compiled are not the engine ones', () {
    // This is the whole point: a subscription that answers both formats can still name
    // different nodes in each, and extra ones only in the xray build.
    final servers = xrayConfigServers(config());
    expect(servers.map((s) => s['name']), isNot(contains('Auto Europa')));
  });

  test('a config without outbounds yields nothing instead of throwing', () {
    expect(xrayConfigServers(const {}), isEmpty);
    expect(xrayConfigGroups(const {'outbounds': 'nonsense'}), isEmpty);
  });
}
