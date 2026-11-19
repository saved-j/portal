import 'dart:io';

import 'package:fl_clash/core/xray_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the panel note under a server name', () {
    test('meta.serverDescription is the note the clients show', () {
      const body = '''
      [{"remarks":"🇪🇪 Эстония","meta":{"serverDescription":"Максимальная скорость"},
        "inbounds":[{"port":10808,"protocol":"socks","settings":{"udp":true}}],
        "outbounds":[{"tag":"node","protocol":"vless",
          "settings":{"vnext":[{"address":"ee.example","port":443,"users":[{"id":"u"}]}]}}]}]
      ''';
      final servers = parseXraySubscription(body);
      expect(servers, hasLength(1));
      expect(servers.first.name, '🇪🇪 Эстония');
      expect(servers.first.description, 'Максимальная скорость');
      expect(servers.first.described, isTrue);
    });

    test('a note after the separator in remarks is read too', () {
      const body = '''
      [{"remarks":"🇵🇱 Польша · Глобальный Ютуб",
        "inbounds":[{"port":10808,"protocol":"socks"}],
        "outbounds":[{"tag":"node","protocol":"vless",
          "settings":{"vnext":[{"address":"pl.example","port":443,"users":[{"id":"u"}]}]}}]}]
      ''';
      final servers = parseXraySubscription(body);
      expect(servers.first.name, '🇵🇱 Польша');
      expect(servers.first.description, 'Глобальный Ютуб');
      expect(servers.first.described, isTrue);
    });

    test('no note at all is not invented: the transport stands in and says so', () {
      const body = '''
      [{"remarks":"🇸🇪 Швеция",
        "inbounds":[{"port":10808,"protocol":"socks"}],
        "outbounds":[{"tag":"node","protocol":"vless",
          "settings":{"vnext":[{"address":"se.example","port":443,"users":[{"id":"u"}]}]},
          "streamSettings":{"network":"ws","security":"tls"}}]}]
      ''';
      final servers = parseXraySubscription(body);
      expect(servers.first.described, isFalse);
    });
  });

  test('a real panel body carries a note for every server', () {
    // A body saved from a live panel (Happ client name). Skipped when it is absent: the file is
    // a local probe, not part of the repository.
    final file = File('/tmp/sub_Happ-2.9.1.bin');
    if (!file.existsSync()) {
      return;
    }
    final servers = parseXraySubscription(file.readAsStringSync());
    expect(servers, hasLength(24));
    expect(servers.every((server) => server.described), isTrue);
    expect(servers[1].name, '🇪🇪 Эстония');
    expect(servers[1].description, 'Максимальная скорость');
    expect(servers[2].description, 'Глобальный ютуб');
  });
}
