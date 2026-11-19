import 'package:fl_clash/core/xray_subscription.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  XrayServerConfig server(String remarks, String note) => XrayServerConfig(
        name: remarks,
        description: note,
        protocol: 'vless',
        address: 'a.example',
        port: 443,
        config: const {'outbounds': []},
      );

  group('PortalNoteIndex', () {
    test('a note written for one list is found by the other list name', () {
      // The Xray document names its servers with the flag; the engine document names the
      // same servers without it. One server, one note.
      final index = PortalNoteIndex.ofServers([
        server('🇪🇪 Эстония', 'Максимальная скорость'),
        server('🇫🇮 Финляндия', 'Глобальный ютуб'),
      ]);
      expect(index.noteFor('Эстония'), 'Максимальная скорость');
      expect(index.noteFor('🇪🇪 Эстония'), 'Максимальная скорость');
      expect(index.noteFor('Финляндия'), 'Глобальный ютуб');
    });

    test('a server the panel did not describe has no note to borrow', () {
      final index = PortalNoteIndex.ofServers([server('🇸🇪 Швеция', '')]);
      expect(index.noteFor('Швеция'), '');
      expect(index.isEmpty, isTrue);
    });

    test('names are matched whole: Эстония 2 is not Эстония', () {
      final index = PortalNoteIndex.ofServers([
        server('🇪🇪 Эстония', 'Максимальная скорость'),
      ]);
      expect(index.noteFor('Эстония 2'), '');
    });

    test('the key ignores the flag and extra spaces, not the name', () {
      expect(PortalNoteIndex.keyOf('🇭🇰 Гонконг'), 'Гонконг');
      expect(PortalNoteIndex.keyOf('Гонконг  '), 'Гонконг');
      expect(PortalNoteIndex.keyOf('Гонконг'), 'Гонконг');
    });
  });
}
