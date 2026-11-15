import 'package:fl_clash/core/proxy_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('endpoints come from the proxies list, name by name', () {
    const body = '''
proxies:
  - name: EE-1
    type: vless
    server: ee.example.com
    port: 443
  - name: FI-1
    type: trojan
    server: fi.example.net
    port: "8443"
  - name: no-server
    type: ss
''';
    final endpoints = parseProxyEndpoints(body);
    expect(endpoints['EE-1']!.host, 'ee.example.com');
    expect(endpoints['EE-1']!.port, 443);
    expect(endpoints['FI-1']!.port, 8443, reason: 'a quoted port still parses');
    expect(endpoints.containsKey('no-server'), isFalse);
  });

  test('a body that is not a config yields nothing instead of guessing', () {
    expect(parseProxyEndpoints('Subscription is unavailable'), isEmpty);
    expect(parseProxyEndpoints(''), isEmpty);
    expect(parseProxyEndpoints('{"not":"yaml proxies"}'), isEmpty);
  });
}
