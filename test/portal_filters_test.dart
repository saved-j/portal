import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/views/dashboard/portal_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  group('PortalFilters provider', () {
    test('hiding a chip is written to the settings', () {
      container.read(portalFiltersProvider.notifier).toggle('AI');
      expect(container.read(appSettingProvider).portalHiddenFiltersRules, ['AI']);
      expect(container.read(portalFiltersProvider).hidden, {'AI'});
    });

    test('a hidden chip stays hidden after a restart', () {
      container.read(portalFiltersProvider.notifier).toggle('AI');
      // A restart is a new container that reads the settings the previous run left on
      // disk; the value below is exactly what was written, after a trip through JSON.
      final stored = AppSettingProps.fromJson(
        Map<String, dynamic>.from(container.read(appSettingProvider).toJson())
          // The filters list is stored as objects that `toJson` keeps as models; this test
          // is about the hidden names, so that unrelated field is dropped rather than made
          // to round-trip here.
          ..remove('filters'),
      );
      expect(stored.portalHiddenFiltersRules, ['AI']);
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);
      restarted.read(appSettingProvider.notifier).value = stored;
      expect(restarted.read(portalFiltersProvider).hidden, {'AI'});
    });

    test('the order is written too', () {
      container.read(portalFiltersProvider.notifier).reorder(['b', 'a']);
      expect(container.read(appSettingProvider).portalFilterOrderRules, ['b', 'a']);
    });

    test('the two modes keep their own hidden chips', () {
      container.read(portalFiltersProvider.notifier).toggle('AI');
      container
          .read(patchClashConfigProvider.notifier)
          .update((config) => config.copyWith(mode: Mode.global));
      expect(container.read(portalFiltersProvider).hidden, isEmpty);
      container.read(portalFiltersProvider.notifier).toggle('Всё остальное');
      final stored = container.read(appSettingProvider);
      expect(stored.portalHiddenFiltersRules, ['AI']);
      expect(stored.portalHiddenFiltersXray, ['Всё остальное']);
    });
  });
}
