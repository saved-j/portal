import 'package:flutter_test/flutter_test.dart';
import 'package:fl_clash/core/update_backoff.dart';

void main() {
  group('updateBackoffAfter', () {
    test('no failures means no wait', () {
      expect(updateBackoffAfter(0), Duration.zero);
    });

    test('the wait grows an hour per failure up to four', () {
      expect(updateBackoffAfter(1), const Duration(hours: 1));
      expect(updateBackoffAfter(2), const Duration(hours: 2));
      expect(updateBackoffAfter(3), const Duration(hours: 3));
    });

    test('it stops growing at four hours', () {
      expect(updateBackoffAfter(4), const Duration(hours: 4));
      expect(updateBackoffAfter(17), const Duration(hours: 4));
    });
  });

  group('updateFailureNote', () {
    test('says the subscription keeps working and names the next attempt', () {
      final note = updateFailureNote(
        failures: 2,
        nextAttempt: DateTime(2026, 11, 19, 14, 5),
        ru: true,
        reason: 'DioException(unknown)',
      );
      expect(note, contains('автономном режиме'));
      expect(note, contains('14:05'));
      expect(note, isNot(contains('непригоден')));
    });

    test('a failure count of zero passes the reason through unchanged', () {
      expect(
        updateFailureNote(
          failures: 0,
          nextAttempt: DateTime(2026),
          ru: false,
          reason: 'http 502',
        ),
        'http 502',
      );
    });
  });
}
