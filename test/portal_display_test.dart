import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/dashboard/portal_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('PortalDisplay provider', () {
    test('default is the name + server + icon layout', () {
      expect(container.read(portalDisplayProvider), 2);
    });

    test('a stored layout is what the chips read back', () {
      container
          .read(appSettingProvider.notifier)
          .update((settings) => settings.copyWith(portalDisplay: 4));
      expect(container.read(portalDisplayProvider), 4);
    });

    test('cycling writes the next layout into the settings', () {
      container.read(portalDisplayProvider.notifier).cycle();
      expect(container.read(appSettingProvider).portalDisplay, 3);
      expect(container.read(portalDisplayProvider), 3);
    });

    test('cycling wraps around the five layouts', () {
      container
          .read(appSettingProvider.notifier)
          .update((settings) => settings.copyWith(portalDisplay: 4));
      container.read(portalDisplayProvider.notifier).cycle();
      expect(container.read(portalDisplayProvider), 0);
    });
  });

  group('AppSetting layout storage', () {
    test('the chosen layout is written to and read from JSON', () {
      expect(AppSettingProps(portalDisplay: 4).toJson()['portalDisplay'], 4);
      expect(
        AppSettingProps.fromJson(const {'portalDisplay': 4}).portalDisplay,
        4,
      );
    });

    test('a settings file without the field falls back to the default', () {
      final restored = AppSettingProps.fromJson(const {});
      expect(restored.portalDisplay, 2);
    });
  });
}
