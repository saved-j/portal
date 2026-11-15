import 'dart:io';

import 'package:fl_clash/core/xray_ping.dart';
import 'package:flutter_test/flutter_test.dart';

/// The number on a simple-portal row is a request the child carries, timed to its first byte.
/// These tests pin the two halves of that promise: a request that comes back produces a number
/// and names what it asked for, and a request that cannot come back produces a dash — never a
/// number the phone made up.
void main() {
  late HttpServer server;
  late String url;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 204;
      await request.response.close();
    });
    url = 'http://127.0.0.1:${server.port}/generate_204';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('a request that answers is a number, and the line names what it timed', () async {
    final probe = await probeThroughPortal(url);
    expect(probe.note, PortalDelayNote.measured);
    expect(probe.ms, isNotNull);
    expect(probe.ms, greaterThanOrEqualTo(0));
    expect(probe.describe(), contains('generate_204'));
    expect(probe.describe(), contains('ms'));
  });

  test('a port nothing listens on is a dash, not a small number', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    final probe = await probeThroughPortal('http://127.0.0.1:$port/generate_204');
    expect(probe.ms, isNull);
    expect(probe.note, isNot(PortalDelayNote.measured));
  });

  test('nothing to request is not a measurement', () async {
    expect((await probeThroughPortal('')).note, PortalDelayNote.noUrl);
    expect((await probeThroughPortal('not a url')).note, PortalDelayNote.noUrl);
  });

  test('the default note for a silent tunnel is its own reason, not a zero', () {
    const silent = PortalDelay(url: 'https://x/generate_204', note: PortalDelayNote.noTunnel);
    expect(silent.ms, isNull);
    expect(silent.describe(), contains('no tunnel'));
  });
}
