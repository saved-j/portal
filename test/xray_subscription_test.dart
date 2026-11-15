import 'dart:convert';

import 'package:fl_clash/core/xray_subscription.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules here come from the Incy developer docs: an array of full xray configurations,
/// where each element is a separate server, named after its first proxy outbound.
void main() {
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

  test('without remarks the first proxy outbound still names the server', () {
    expect(parseXraySubscription(jsonEncode(config('KR-1'))).single.name, 'KR-1');
  });

  test('a body that is not a configuration yields nothing', () {
    expect(parseXraySubscription(''), isEmpty);
    expect(parseXraySubscription('<html>502</html>'), isEmpty);
    expect(parseXraySubscription('{"hasMihomo":true}'), isEmpty);
    expect(parseXraySubscription('[]'), isEmpty);
  });
}
