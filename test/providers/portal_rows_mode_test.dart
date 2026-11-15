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

  group('the drawn group says where it came from, and whose it is', () {
    Group groupOf(String name) => Group(
      type: GroupType.Selector,
      name: 'PORTAL',
      all: [Proxy(name: name, type: 'vless')],
    );

    OwnedGroup owned(String name, RowsOwner owner) =>
        (group: groupOf(name), owner: owner);

    test('the current owner wins and is called live', () {
      final shown = portalShownRows(
        mode: RowsOwner.engine,
        live: owned('live-row', RowsOwner.engine),
        held: null,
        fallbacks: const [],
      );
      expect(shown.source, 'live');
      expect(shown.owner, RowsOwner.engine);
      expect(shown.group!.all.single.name, 'live-row');
    });

    test('a live answer from the other owner is not an answer', () {
      // The engine's groups stay in memory after the engine stops; the simple portal must not
      // draw them, and vice versa.
      final shown = portalShownRows(
        mode: RowsOwner.child,
        live: owned('engine-row', RowsOwner.engine),
        held: null,
        fallbacks: [
          ('servers', groupOf('child-row')),
        ],
      );
      expect(shown.source, 'servers');
      expect(shown.group!.all.single.name, 'child-row');
    });

    test('a held group from the other owner is not read', () {
      final shown = portalShownRows(
        mode: RowsOwner.engine,
        live: null,
        held: owned('child-row', RowsOwner.child),
        fallbacks: [
          ('profile', groupOf('engine-row')),
        ],
      );
      expect(shown.source, 'profile');
      expect(shown.group!.all.single.name, 'engine-row');
    });

    test('an empty live answer keeps the own held rows', () {
      final shown = portalShownRows(
        mode: RowsOwner.engine,
        live: null,
        held: owned('held-row', RowsOwner.engine),
        fallbacks: [
          ('cache', groupOf('cache-row')),
        ],
      );
      expect(shown.source, 'held');
      expect(shown.group!.all.single.name, 'held-row');
    });

    test('with nothing held, the fallbacks answer in the order given', () {
      expect(
        portalShownRows(
          mode: RowsOwner.engine,
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
          mode: RowsOwner.engine,
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
        mode: RowsOwner.child,
        live: null,
        held: null,
        fallbacks: const [],
      );
      expect(shown.group, isNull);
      expect(shown.source, 'none');
      expect(shown.owner, RowsOwner.child);
    });

    test('an empty group is not an answer', () {
      final empty = Group(type: GroupType.Selector, name: 'PORTAL', all: const []);
      expect(
        portalShownRows(
          mode: RowsOwner.engine,
          live: (group: empty, owner: RowsOwner.engine),
          held: null,
          fallbacks: const [],
        ).source,
        'none',
      );
    });

    test('the group this owner drew is the one it remembers', () {
      OwnedGroup? kept;
      portalShownRows(
        mode: RowsOwner.engine,
        live: owned('live-row', RowsOwner.engine),
        held: null,
        fallbacks: const [],
        remember: (value) => kept = value,
      );
      expect(kept!.owner, RowsOwner.engine);
      expect(kept!.group.all.single.name, 'live-row');
    });
  });

  group('this app\'s own service nodes are never rows', () {
    test('XRAY-SOCKS and PORTAL-XRAY are refused by name', () {
      expect(isPortalServiceNode('XRAY-SOCKS'), isTrue);
      expect(isPortalServiceNode('portal-xray'), isTrue);
      expect(isPortalServiceNode(' VPN - Main '), isFalse);
      expect(isPortalServiceNode('Auto Europe'), isFalse);
    });

    test('a group carrying them draws the subscription\'s rows only', () {
      final group = portalGroupOfRows(const [
        PortalRow(name: 'XRAY-SOCKS', type: 'Socks5'),
        PortalRow(name: 'PORTAL-XRAY', type: 'Selector'),
        PortalRow(name: 'Эстония', type: 'Vless'),
        PortalRow(name: 'DIRECT', type: 'Direct'),
      ]);
      expect(group.all.map((proxy) => proxy.name), ['Эстония']);
    });

    test('a profile that somehow carries one does not offer it', () {
      final rows = parsePortalRows('''
proxies:
  - {name: XRAY-SOCKS, type: socks5, server: 127.0.0.1, port: 10808}
  - {name: Эстония, type: vless, server: ee.example, port: 443}
''');
      expect(rows.map((row) => row.name), ['Эстония']);
    });
  });
}
