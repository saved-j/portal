import 'package:fl_clash/core/sweep_ledger.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sweep writes rows into one map, and two sweeps writing into it is a defect the audit
/// found twice: a cancelled sweep that kept its number came back to life, and a profile
/// change left another subscription's dates looking fresh. These tests pin the rules.
void main() {
  late DateTime clock;
  late SweepLedger ledger;

  setUp(() {
    clock = DateTime(2026, 11, 16, 12);
    ledger = SweepLedger(now: () => clock);
  });

  group('a sweep is current only while it is the newest', () {
    test('beginning a sweep supersedes the previous one', () {
      final first = ledger.begin(Mode.rule);
      expect(ledger.isCurrent(first, Mode.rule), isTrue);

      final second = ledger.begin(Mode.rule);
      expect(ledger.isCurrent(first, Mode.rule), isFalse);
      expect(ledger.isCurrent(second, Mode.rule), isTrue);
    });

    test('a cancelled sweep never becomes current again', () {
      final first = ledger.begin(Mode.global);
      ledger.cancel();
      final second = ledger.begin(Mode.global);

      // The number the cancelled sweep held is not the newest one any more — the defect was
      // that it was: cancelling reset the id, so the next sweep took the same number.
      expect(first, isNot(second));
      expect(ledger.isCurrent(first, Mode.global), isFalse);
      expect(ledger.isCurrent(second, Mode.global), isTrue);
    });

    test('a sweep does not answer for the other mode', () {
      final sweep = ledger.begin(Mode.rule);
      expect(ledger.isCurrent(sweep, Mode.global), isFalse);
    });

    test('a mode switch supersedes the sweep that was running', () {
      final sweep = ledger.begin(Mode.rule);
      ledger.cancel();
      expect(ledger.isCurrent(sweep, Mode.rule), isFalse);
      expect(ledger.mode, isNull);
    });
  });

  group('a number is a fact with a date', () {
    test('a row is fresh for two minutes, not longer', () {
      ledger.record('Эстония', 120);
      expect(ledger.isFresh('Эстония'), isTrue);

      clock = clock.add(const Duration(minutes: 1, seconds: 59));
      expect(ledger.isFresh('Эстония'), isTrue);

      clock = clock.add(const Duration(seconds: 2));
      expect(ledger.isFresh('Эстония'), isFalse);
    });

    test('a dash counts as measured', () {
      ledger.record('Мёртвый узел', null);
      expect(ledger.isFresh('Мёртвый узел'), isTrue);
    });

    test('an unknown row is not fresh', () {
      expect(ledger.isFresh('Никогда не мерили'), isFalse);
    });
  });

  group('a deliberate press ignores the window', () {
    test('a fresh row is measured again when forced', () {
      ledger.record('Эстония', 120);
      expect(ledger.needsMeasurement('Эстония'), isFalse);
      expect(ledger.needsMeasurement('Эстония', force: true), isTrue);
    });

    test('a stale row is measured anyway', () {
      ledger.record('Эстония', 120);
      clock = clock.add(const Duration(minutes: 3));
      expect(ledger.needsMeasurement('Эстония'), isTrue);
    });
  });

  group('the same list is not swept twice', () {
    test('asking again for the same names inside the window is skipped', () {
      expect(ledger.shouldStart(Mode.global, 'a|b'), isTrue);
      ledger.markStarted(Mode.global, 'a|b');
      expect(ledger.shouldStart(Mode.global, 'a|b'), isFalse);

      clock = clock.add(const Duration(minutes: 2, seconds: 1));
      expect(ledger.shouldStart(Mode.global, 'a|b'), isTrue);
    });

    test('a different list or another mode is a new sweep', () {
      ledger.markStarted(Mode.global, 'a|b');
      expect(ledger.shouldStart(Mode.global, 'a|b|c'), isTrue);
      expect(ledger.shouldStart(Mode.rule, 'a|b'), isTrue);
    });
  });

  group('another profile is another subscription', () {
    test('reset forgets the rows and the dates', () {
      ledger.record('Эстония', 120);
      final sweep = ledger.begin(Mode.rule);

      ledger.reset();

      expect(ledger.isFresh('Эстония'), isFalse);
      expect(ledger.measuredAt, isEmpty);
      expect(ledger.isCurrent(sweep, Mode.rule), isFalse);
    });
  });
}
