import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/core/subscription_availability.dart';
import 'package:flutter_test/flutter_test.dart';

/// A subscription that worked five minutes ago must survive a bad answer from the panel.
/// These tests describe what counts as "usable" before anything on disk is replaced.
void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('an error page is not a usable body', () {
    expect(parseShareLinks('Подписка временно недоступна'), isEmpty);
    expect(parseShareLinks('<html>502 Bad Gateway</html>'), isEmpty);
  });

  test('an empty body is not usable', () {
    expect(parseShareLinks(''), isEmpty);
    expect(parseShareLinks('   \n\t '), isEmpty);
  });

  test('a real node list is usable', () {
    final body = bytes('vless://uuid@host:443?security=reality&pbk=K&sid=1#Node');
    expect(parseShareLinks(utf8.decode(body)), isNotEmpty);
  });

  test('a partial list with one broken line still keeps the good node', () {
    final nodes = parseShareLinks(
      'vless://\n'
      'vless://uuid@good.example.net:443#Good\n'
      'not-a-link\n',
    );
    expect(nodes, hasLength(1));
    expect(nodes.single['name'], 'Good');
  });

  test('a clash yaml body is never mistaken for a node list', () {
    const yaml = 'proxies:\n  - name: a\n    type: vless\n';
    expect(parseShareLinks(yaml), isEmpty);
  });
}
