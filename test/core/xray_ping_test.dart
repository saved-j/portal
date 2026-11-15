import 'dart:io';

import 'package:fl_clash/core/xray_ping.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ping is only worth drawing when it is a fact about the server. These tests pin the two
/// cases that made a row lie: a fake-IP from the tunnel's own range, and a loopback address.
void main() {
  InternetAddress v4(String address) => InternetAddress(address);

  group('the tunnel owns these addresses, so they are never timed', () {
    test('the fake-IP range mihomo and Xray answer with', () {
      expect(isTunnelOwnedAddress(v4('198.18.0.1')), isTrue);
      expect(isTunnelOwnedAddress(v4('198.18.0.2')), isTrue);
      expect(isTunnelOwnedAddress(v4('198.18.44.7')), isTrue);
      expect(isTunnelOwnedAddress(v4('198.19.255.255')), isTrue);
    });

    test('loopback, the unspecified address and link-local', () {
      expect(isTunnelOwnedAddress(v4('127.0.0.1')), isTrue);
      expect(isTunnelOwnedAddress(v4('0.0.0.0')), isTrue);
      expect(isTunnelOwnedAddress(v4('169.254.1.1')), isTrue);
      expect(isTunnelOwnedAddress(InternetAddress.loopbackIPv6), isTrue);
    });

    test('a real server address is not the tunnel', () {
      expect(isTunnelOwnedAddress(v4('185.155.222.5')), isFalse);
      expect(isTunnelOwnedAddress(v4('1.1.1.1')), isFalse);
      expect(isTunnelOwnedAddress(v4('198.17.0.1')), isFalse);
      expect(isTunnelOwnedAddress(v4('198.20.0.1')), isFalse);
      expect(isTunnelOwnedAddress(InternetAddress('2a01:4f8::1')), isFalse);
    });
  });

  group('a fake address is a dash, never a number', () {
    test('a literal fake-IP is refused before any handshake', () async {
      final probe = await probeTcp('198.18.0.5', 443);
      expect(probe.note, TcpPingNote.fakeAddress);
      expect(probe.ms, isNull);
      expect(probe.answered, isFalse);
      expect(probe.describe(), contains('the tunnel'));
    });

    test('a literal loopback is refused too', () async {
      final probe = await probeTcp('127.0.0.1', 7890);
      expect(probe.note, TcpPingNote.fakeAddress);
      expect(probe.ms, isNull);
    });

    test('nothing to measure is not a measurement', () async {
      expect((await probeTcp('', 443)).note, TcpPingNote.noAddress);
      expect((await probeTcp('node.example', 0)).note, TcpPingNote.noAddress);
    });
  });
}
