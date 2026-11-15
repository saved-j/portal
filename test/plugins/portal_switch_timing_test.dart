import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/portal_switch_timing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The switch's clock has one job and it is a measurement: exactly one `switchStart` per tap,
/// at most one `phase=list` line per tap, and nothing at all when there was no tap. A clock
/// that wrote a line twice, or wrote one for a screen that merely rebuilt, would turn the
/// number the owner reads into an average of things that did not happen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/portal');

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    portalSwitchClock.end();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    portalSwitchClock.end();
  });

  test('a tap starts the record clock once, wherever it is going', () async {
    portalSwitchClock.begin(toSimple: false);
    portalSwitchClock.begin(toSimple: true);
    await Future<void>.delayed(Duration.zero);

    final starts = calls.where((call) => call.method == 'switchStart').toList();
    expect(starts, hasLength(2));
    expect((starts.first.arguments as Map)['to'], 'rule');
    expect((starts.last.arguments as Map)['to'], 'global');
  });

  test('the list line is written once per tap and names its source', () async {
    portalSwitchClock.begin(toSimple: false);
    await Future<void>.delayed(Duration.zero);

    portalSwitchClock.listPopulated(mode: 'rule', source: 'held', rows: 27);
    portalSwitchClock.listPopulated(
      mode: 'global',
      source: 'live',
      rows: 27,
    );
    await Future<void>.delayed(Duration.zero);

    final timed = calls.where((call) => call.method == 'switchTiming').toList();
    expect(timed, hasLength(1));
    final arguments = timed.single.arguments as Map;
    expect(arguments['phase'], 'list');
    expect(arguments['detail'], 'mode=rule source=held rows=27');
    expect(arguments['durationMs'], isA<int>());
  });

  test('a screen with no tap behind it writes nothing', () async {
    portalSwitchClock.listPopulated(mode: 'rule', source: 'profile', rows: 3);
    await Future<void>.delayed(Duration.zero);

    expect(calls.where((call) => call.method == 'switchTiming'), isEmpty);
  });

  test('a switch that failed stops its clock instead of writing a length', () async {
    portalSwitchClock.begin(toSimple: true);
    portalSwitchClock.end();
    portalSwitchClock.listPopulated(mode: 'global', source: 'held', rows: 27);
    await Future<void>.delayed(Duration.zero);

    expect(calls.where((call) => call.method == 'switchTiming'), isEmpty);
  });
}
