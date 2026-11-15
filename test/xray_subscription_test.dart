import 'dart:convert';

import 'package:fl_clash/core/xray_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules here come from the Incy developer docs: an array of full xray configurations,
/// where each element is a separate server, named after its first proxy outbound.
void main() {
  group('endpoint', _endpointCases);
  Map<String, dynamic> config(String tag, {String description = '', String remarks = ''}) => {
        if (remarks.isNotEmpty) 'remarks': remarks,
        'meta': {'serverDescription': description},
        'inbounds': [
          {'tag': 'socks-in', 'protocol': 'socks', 'port': 10808},
        ],
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
          {'tag': tag, 'protocol': 'vless', 'settings': {}},
          {'tag': 'block', 'protocol': 'blackhole'},
        ],
      };

  test('each element of the array is a server', () {
    final body = jsonEncode([config('Эстония'), config('Финляндия')]);
    final servers = parseXraySubscription(body);
    expect(servers, hasLength(2));
    expect(servers.first.name, 'Эстония');
    expect(servers.last.name, 'Финляндия');
  });

  test('the name is the first proxy outbound, not direct', () {
    final servers = parseXraySubscription(jsonEncode(config('Германия')));
    expect(servers.single.name, 'Германия');
  });

  test('the description comes from meta.serverDescription', () {
    final servers = parseXraySubscription(
      jsonEncode(config('Нидерланды', description: 'Работает Gemini')),
    );
    expect(servers.single.description, 'Работает Gemini');
    expect(servers.single.label, 'Нидерланды · Работает Gemini');
  });

  test('a flag from meta is shown in front of the name', () {
    final item = config('Эстония');
    (item['meta'] as Map)['serverFlag'] = '🇪🇪';
    final server = parseXraySubscription(jsonEncode(item)).single;
    expect(server.label, '🇪🇪 Эстония');
  });

  test('the whole element is kept, since it is what the core runs', () {
    final body = jsonEncode([config('KR')]);
    final server = parseXraySubscription(body).single;
    expect((server.config['outbounds'] as List), hasLength(3));
    expect((server.config['inbounds'] as List), hasLength(1));
  });

  test('the panel name comes from remarks, split at the middle dot', () {
    final server = parseXraySubscription(
      jsonEncode(config('proxy', remarks: '🇪🇪 Эстония · Максимальная скорость')),
    ).single;
    expect(server.name, '🇪🇪 Эстония');
    expect(server.description, 'Максимальная скорость');
  });

  test('the pipe separator the docs show is understood too', () {
    final server = parseXraySubscription(
      jsonEncode(config('proxy', remarks: '🇵🇱 Poland | TCP')),
    ).single;
    expect(server.name, '🇵🇱 Poland');
    expect(server.description, 'TCP');
  });

  test('without remarks the first proxy outbound still names the server', () {
    expect(parseXraySubscription(jsonEncode(config('KR-1'))).single.name, 'KR-1');
  });

  test('the protocol comes from the config, not from the core', () {
    final vless = parseXraySubscription(jsonEncode(config('EE'))).single;
    expect(vless.protocol, 'vless');

    final hy2 = {
      'remarks': '🇫🇮 Финляндия',
      'outbounds': [
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'hy', 'protocol': 'hysteria2', 'settings': {}},
      ],
    };
    expect(parseXraySubscription(jsonEncode(hy2)).single.protocol, 'hysteria2');
  });

  test('without meta a transport still describes the server', () {
    final item = config('DE');
    (item['outbounds'] as List)[1] = {
      'tag': 'de',
      'protocol': 'vless',
      'settings': {},
      'streamSettings': {'network': 'xhttp'},
    };
    expect(parseXraySubscription(jsonEncode(item)).single.description, 'XHTTP');
  });

  test('a body that is not a configuration yields nothing', () {
    expect(parseXraySubscription(''), isEmpty);
    expect(parseXraySubscription('<html>502</html>'), isEmpty);
    expect(parseXraySubscription('{"hasMihomo":true}'), isEmpty);
    expect(parseXraySubscription('[]'), isEmpty);
  });
}

void _endpointCases() {
  test('endpoint comes from the transport outbound, not the routers', () {
    final servers = parseXraySubscription(jsonEncode([
      {
        'remarks': '🇪🇪 Эстония · Максимальная скорость',
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {'address': 'ee1.example.com', 'port': 443},
              ],
            },
          },
        ],
      },
      {
        'remarks': '🇫🇮 Финляндия',
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'trojan',
            'settings': {
              'servers': [
                {'address': 'fi.example.net', 'port': '8443'},
              ],
            },
          },
        ],
      },
      {
        'remarks': 'пустой',
        'outbounds': [
          {'tag': 'direct', 'protocol': 'freedom'},
        ],
      },
    ]));
    expect(servers[0].address, 'ee1.example.com');
    expect(servers[0].port, 443);
    expect(servers[1].address, 'fi.example.net');
    expect(servers[1].port, 8443, reason: 'a port written as text still parses');
    expect(servers[2].address, isEmpty);
    expect(servers[2].port, 0);
  });
}
