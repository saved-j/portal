import 'dart:convert';

import 'package:fl_clash/core/xray_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests describe the mapping the app relies on: a Clash proxy entry in, an Xray
/// outbound out. They run without a phone, a tunnel or a panel.
void main() {
  test('vless over ws with tls keeps every field the server needs', () {
    final json = xrayConfigJson({
      'name': 'EE-1',
      'type': 'vless',
      'server': 'ee1.example.net',
      'port': 443,
      'uuid': '11111111-2222-3333-4444-555555555555',
      'network': 'ws',
      'tls': true,
      'servername': 'cdn.example.net',
      'ws-path': '/ray',
      'ws-headers': {'Host': 'cdn.example.net'},
      'client-fingerprint': 'chrome',
    });
    final config = jsonDecode(json) as Map<String, dynamic>;
    final outbound = (config['outbounds'] as List).first as Map<String, dynamic>;

    expect(outbound['protocol'], 'vless');
    final vnext = (outbound['settings'] as Map)['vnext'] as List;
    expect((vnext.first as Map)['address'], 'ee1.example.net');
    expect((vnext.first as Map)['port'], 443);
    expect(((vnext.first as Map)['users'] as List).first['id'],
        '11111111-2222-3333-4444-555555555555');

    final stream = outbound['streamSettings'] as Map;
    expect(stream['network'], 'ws');
    expect((stream['wsSettings'] as Map)['path'], '/ray');
    expect(stream['security'], 'tls');
    expect((stream['tlsSettings'] as Map)['serverName'], 'cdn.example.net');
  });

  test('reality keeps its public key and short id', () {
    final config = xrayConfigFor({
      'type': 'vless',
      'server': 'r.example.net',
      'port': 443,
      'uuid': 'u',
      'network': 'tcp',
      'tls': true,
      'servername': 'www.microsoft.com',
      'client-fingerprint': 'firefox',
      'reality-opts': {'public-key': 'PUBKEY', 'short-id': 'ab12'},
    });
    final stream = ((config['outbounds'] as List).first
        as Map<String, dynamic>)['streamSettings'] as Map;
    expect(stream['security'], 'reality');
    final reality = stream['realitySettings'] as Map;
    expect(reality['publicKey'], 'PUBKEY');
    expect(reality['shortId'], 'ab12');
    expect(reality['serverName'], 'www.microsoft.com');
    expect(reality['fingerprint'], 'firefox');
  });

  test('trojan carries a password and a grpc transport', () {
    final config = xrayConfigFor({
      'type': 'trojan',
      'server': 't.example.net',
      'port': '8443',
      'password': 'secret',
      'network': 'grpc',
      'grpc-service-name': 'svc',
    });
    final outbound = (config['outbounds'] as List).first as Map;
    expect(outbound['protocol'], 'trojan');
    final server = ((outbound['settings'] as Map)['servers'] as List).first as Map;
    expect(server['port'], 8443); // a string port is accepted and normalised
    expect(server['password'], 'secret');
    expect((outbound['streamSettings'] as Map)['network'], 'grpc');
    expect(((outbound['streamSettings'] as Map)['grpcSettings'] as Map)['serviceName'],
        'svc');
  });

  test('the socks inbound is always present and bound to localhost', () {
    final config = xrayConfigFor({
      'type': 'vless',
      'server': 's',
      'port': 1,
      'uuid': 'u',
    }, socksPort: 10808);
    final inbound = (config['inbounds'] as List).first as Map;
    expect(inbound['protocol'], 'socks');
    expect(inbound['listen'], '127.0.0.1');
    expect(inbound['port'], 10808);
  });

  test('an unknown protocol is refused instead of silently producing nothing', () {
    expect(
      () => xrayConfigFor({'type': 'ss', 'server': 's', 'port': 1}),
      throwsA(isA<UnsupportedProxyType>()),
    );
  });
}
