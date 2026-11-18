import 'package:fl_clash/core/auto_ping_interval.dart';
import 'package:flutter_test/flutter_test.dart';

/// The switch's number must reach exactly the groups that time themselves, and must never
/// overwrite a provider's choice — those two rules are what make "as in the subscription" mean
/// something.
void main() {
  Map<String, dynamic> document(List<Map<String, dynamic>> groups) => {
        'proxy-groups': groups,
      };

  test('a url-test with interval 0 takes the owner period', () {
    final doc = document([
      {'name': 'Авто', 'type': 'url-test', 'interval': 0},
    ]);
    expect(applyAutoPingInterval(doc, 90), 1);
    expect(doc['proxy-groups'][0]['interval'], 90);
  });

  test('a url-test without an interval takes it too', () {
    final doc = document([
      {'name': 'Авто', 'type': 'url-test'},
    ]);
    expect(applyAutoPingInterval(doc, 60), 1);
    expect(doc['proxy-groups'][0]['interval'], 60);
  });

  test("a provider's own number is kept", () {
    final doc = document([
      {'name': 'Авто', 'type': 'url-test', 'interval': 180},
    ]);
    expect(applyAutoPingInterval(doc, 60), 0);
    expect(doc['proxy-groups'][0]['interval'], 180);
  });

  test('a select group is left alone: it has no clock', () {
    final doc = document([
      {'name': 'Выбор', 'type': 'select'},
    ]);
    expect(applyAutoPingInterval(doc, 60), 0);
    expect(doc['proxy-groups'][0].containsKey('interval'), isFalse);
  });

  test('fallback and load-balance are timed groups as well', () {
    final doc = document([
      {'name': 'A', 'type': 'fallback', 'interval': 0},
      {'name': 'B', 'type': 'load-balance', 'interval': '0'},
    ]);
    expect(applyAutoPingInterval(doc, 120), 2);
    expect(doc['proxy-groups'][0]['interval'], 120);
    expect(doc['proxy-groups'][1]['interval'], 120);
  });

  test('no opinion changes nothing', () {
    final doc = document([
      {'name': 'Авто', 'type': 'url-test', 'interval': 0},
    ]);
    expect(applyAutoPingInterval(doc, null), 0);
    expect(doc['proxy-groups'][0]['interval'], 0);
  });

  test('zero is never written, even if it is asked for', () {
    final doc = document([
      {'name': 'Авто', 'type': 'url-test', 'interval': 0},
    ]);
    expect(applyAutoPingInterval(doc, 0), 0);
    expect(doc['proxy-groups'][0]['interval'], 0);
  });
}
