import 'package:fl_clash/core/xray_bridge_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> base() => {
        'mode': 'rule',
        'proxies': [
          {'name': 'node-a', 'type': 'vless', 'server': 'a', 'port': 443},
        ],
        'proxy-groups': [
          {'name': 'Auto', 'type': 'url-test', 'proxies': ['node-a']},
        ],
        'rules': ['DOMAIN-SUFFIX,vk.com,Auto'],
      };

  test('the bridge adds one socks proxy and one group, and forces global mode', () {
    final wrapped = withXrayBridge(base());
    final proxies = wrapped['proxies'] as List;
    final groups = wrapped['proxy-groups'] as List;

    expect(proxies.length, 2);
    final bridge = proxies.last as Map;
    expect(bridge['name'], xrayBridgeTag);
    expect(bridge['type'], 'socks5');
    expect(bridge['server'], '127.0.0.1');
    expect(bridge['port'], 10808);

    expect(groups.length, 2);
    expect((groups.last as Map)['proxies'], [xrayBridgeTag]);
    expect(wrapped['mode'], 'global');
    expect(wrapped['GLOBAL'], xrayBridgeGroup);

    // the subscription's own entries are still there, just unused in global mode
    expect((proxies.first as Map)['name'], 'node-a');
  });

  test('the original config is left untouched', () {
    final original = base();
    withXrayBridge(original);
    expect((original['proxies'] as List).length, 1);
    expect(original['mode'], 'rule');
    expect(original.containsKey('GLOBAL'), isFalse);
  });

  test('wrapping twice does not stack a second bridge', () {
    final once = withXrayBridge(base());
    final twice = withXrayBridge(once);
    final names = (twice['proxies'] as List).map((p) => (p as Map)['name']);
    expect(names.where((n) => n == xrayBridgeTag).length, 1);
    final groups = (twice['proxy-groups'] as List).map((g) => (g as Map)['name']);
    expect(groups.where((n) => n == xrayBridgeGroup).length, 1);
  });

  test('removing the bridge restores the previous mode and drops only its entries', () {
    final wrapped = withXrayBridge(base());
    final restored = withoutXrayBridge(wrapped, restoreMode: 'rule');

    expect(restored['mode'], 'rule');
    expect(restored.containsKey('GLOBAL'), isFalse);
    expect((restored['proxies'] as List).length, 1);
    expect((restored['proxy-groups'] as List).length, 1);
    expect((restored['rules'] as List).length, 1);
  });

  test('a custom port is honoured', () {
    final wrapped = withXrayBridge(base(), port: 2080);
    expect(((wrapped['proxies'] as List).last as Map)['port'], 2080);
  });
}
