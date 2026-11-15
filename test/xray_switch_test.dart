import 'dart:io';

import 'package:fl_clash/core/xray_switch.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = '''
proxies:
  - name: node-a
    type: vless
    server: a.example.net
    port: 443
    uuid: u1
  - name: node-b
    type: trojan
    server: b.example.net
    port: 443
    password: p
proxy-groups:
  - name: Auto
    type: url-test
    proxies: [DIRECT, node-b, node-a]
  - name: Deep
    type: select
    proxies: [Auto]
''';

void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('xray-switch');
    file = File('${dir.path}/config.yaml');
    await file.writeAsString(_config);
  });

  test('a node is read with every key the engine had', () async {
    final node = await nodeDefinitionFor(file.path, 'node-a');
    expect(node, isNotNull);
    expect(node!['type'], 'vless');
    expect(node['server'], 'a.example.net');
    expect(node['uuid'], 'u1');
  });

  test('a group resolves to its first real member, skipping DIRECT', () async {
    final node = await nodeDefinitionFor(file.path, 'Auto');
    expect(node?['name'], 'node-b');
  });

  test('a group inside a group is opened too', () async {
    final node = await nodeDefinitionFor(file.path, 'Deep');
    expect(node?['name'], 'node-b');
  });

  test('a builtin or an unknown name yields nothing instead of a broken child', () async {
    expect(await nodeDefinitionFor(file.path, 'DIRECT'), isNull);
    expect(await nodeDefinitionFor(file.path, 'nope'), isNull);
  });

  test('a missing config is not an exception', () async {
    expect(await nodeDefinitionFor('${file.parent.path}/absent.yaml', 'node-a'), isNull);
  });
}
