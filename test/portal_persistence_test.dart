import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('portalGroupFor', () {
    test('an empty setting means the strip starts on the panel first group', () {
      expect(portalGroupFor(const AppSettingProps(), 7, false), isNull);
    });

    test('a group picked in this profile comes back after a restart', () {
      final settings = withPortalGroup(const AppSettingProps(), 7, false, 'AI');
      expect(portalGroupFor(settings, 7, false), 'AI');
    });

    test('the two modes keep their own open chip', () {
      var settings = withPortalGroup(const AppSettingProps(), 7, false, 'AI');
      settings = withPortalGroup(settings, 7, true, 'Всё остальное');
      expect(portalGroupFor(settings, 7, false), 'AI');
      expect(portalGroupFor(settings, 7, true), 'Всё остальное');
    });

    test('a group named by another profile is not borrowed', () {
      final settings = withPortalGroup(const AppSettingProps(), 7, false, 'AI');
      expect(portalGroupFor(settings, 8, false), isNull);
    });

    test('clearing the open chip leaves nothing to restore', () {
      var settings = withPortalGroup(const AppSettingProps(), 7, false, 'AI');
      settings = withPortalGroup(settings, 7, false, null);
      expect(portalGroupFor(settings, 7, false), isNull);
    });
  });

  group('filter picks', () {
    test('a server picked in a filter is read back for the same profile', () {
      final settings = withPortalRulePick(const AppSettingProps(), 7, 'AI', 'Германия');
      expect(portalRulePickFor(settings, 7, 'AI'), 'Германия');
      expect(portalRulePicksFor(settings, 7), {'AI': 'Германия'});
    });

    test('the xray pick is kept apart from the filter picks', () {
      final settings = withPortalXrayPick(const AppSettingProps(), 7, 'Финляндия');
      expect(portalXrayPickFor(settings, 7), 'Финляндия');
      expect(portalRulePicksFor(settings, 7), isEmpty);
    });

    test('filters of one profile do not leak into another', () {
      final settings = withPortalRulePick(const AppSettingProps(), 7, 'AI', 'Германия');
      expect(portalRulePickFor(settings, 8, 'AI'), '');
      expect(portalXrayPickFor(settings, 8), '');
    });
  });
}
