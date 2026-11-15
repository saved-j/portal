import 'package:fl_clash/core/xray_subscription.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list has two modes and two documents. A row is a name, so the wrong source is not a
/// missing row: it is a real server drawn under the other mode's heading. These tests pin the
/// decision, not the drawing: each mode reads only its own source, and the line that reports
/// which source answered names it.
void main() {
  const servers = [
    XrayServerConfig(
      name: 'Авто-выбор',
      protocol: 'vless',
      address: 'panel.example',
      port: 443,
      config: <String, dynamic>{},
    ),
    XrayServerConfig(
      name: 'Эстония',
      protocol: 'vless',
      address: 'ee.example',
      port: 8443,
      config: <String, dynamic>{},
    ),
  ];

  final engineRows = const [
    PortalRow(name: 'VPN - Main', type: 'Selector'),
    PortalRow(name: '🇫🇮 Финляндия 01', type: 'vless'),
  ];

  group('the fallback belongs to the mode', () {
    test('the simple portal draws the Xray servers and never the engine rows', () {
      final group = portalFallbackGroup(
        simple: true,
        servers: servers,
        engineRows: engineRows,
      );
      expect(group, isNotNull);
      expect(
        group!.all.map((proxy) => proxy.name),
        ['Авто-выбор', 'Эстония'],
      );
    });

    test('the simple portal with no servers has no rows, not the engine ones', () {
      expect(
        portalFallbackGroup(
          simple: true,
          servers: const [],
          engineRows: engineRows,
        ),
        isNull,
      );
    });

    test('the network mode draws the engine body and never an Xray name', () {
      final group = portalFallbackGroup(
        simple: false,
        servers: servers,
        engineRows: engineRows,
      );
      expect(
        group!.all.map((proxy) => proxy.name),
        ['VPN - Main', '🇫🇮 Финляндия 01'],
      );
    });

    test('the network mode with nothing cached is empty, not a guess', () {
      expect(
        portalFallbackGroup(
          simple: false,
          servers: servers,
          engineRows: const [],
        ),
        isNull,
      );
    });
  });

  group('the drawn group says where it came from', () {
    Group groupOf(String name) => Group(
      type: GroupType.Selector,
      name: 'PORTAL',
      all: [Proxy(name: name, type: 'vless')],
    );

    test('the current owner wins and is called live', () {
      final shown = portalShownRows(
        live: groupOf('live-row'),
        held: groupOf('held-row'),
        fallbacks: [('cache', groupOf('cache-row'))],
      );
      expect(shown.source, 'live');
      expect(shown.group!.all.single.name, 'live-row');
    });

    test('an empty answer keeps the held rows', () {
      final shown = portalShownRows(
        live: null,
        held: groupOf('held-row'),
        fallbacks: [('cache', groupOf('cache-row'))],
      );
      expect(shown.source, 'held');
      expect(shown.group!.all.single.name, 'held-row');
    });

    test('with nothing held, the fallbacks answer in the order given', () {
      expect(
        portalShownRows(
          live: null,
          held: null,
          fallbacks: [
            ('cache', null),
            ('profile', groupOf('profile-row')),
          ],
        ).source,
        'profile',
      );
      expect(
        portalShownRows(
          live: null,
          held: null,
          fallbacks: [
            ('cache', groupOf('cache-row')),
            ('profile', groupOf('profile-row')),
          ],
        ).group!.all.single.name,
        'cache-row',
      );
    });

    test('a mode with no rows at all is the honest empty state', () {
      final shown = portalShownRows(
        live: null,
        held: null,
        fallbacks: const [],
      );
      expect(shown.group, isNull);
      expect(shown.source, 'none');
    });

    test('an empty group is not an answer', () {
      final empty = Group(type: GroupType.Selector, name: 'PORTAL', all: const []);
      expect(
        portalShownRows(live: empty, held: null, fallbacks: const []).source,
        'none',
      );
    });
  });
}
