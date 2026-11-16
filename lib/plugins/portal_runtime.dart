import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../common/constant.dart';
import '../common/print.dart';
import '../enum/enum.dart';

/// Who reads the tunnel the Android service established.
///
/// The mode says which owner the app *wants*; this is the owner a generation actually has.
/// They are different questions, and the switch used to answer the second with the first.
enum PortalOwner {
  mihomo('Mihomo'),
  xray('Xray');

  const PortalOwner(this.label);

  /// The spelling the native record uses, so both sides name the same owner.
  final String label;

  static PortalOwner? of(String? value) {
    for (final owner in values) {
      if (owner.label == value || owner.name == value) return owner;
    }
    return null;
  }
}

/// One published state of the portal, as the coordinator wrote it.
///
/// [phase] is one of `Off`, `Starting`, `Active`, `Stopping`, `Failed`. Only `Active` means
/// an owner is reading the tunnel, and it is only published after that owner acknowledged
/// it; `Starting` and `Stopping` mean the portal is in the middle of a transaction.
class PortalRuntimeStatus {
  const PortalRuntimeStatus({
    required this.generation,
    required this.phase,
    this.owner,
    this.fdEpoch = 0,
    this.reason = '',
    this.engine = false,
    this.child = false,
    this.childLine = '',
  });

  const PortalRuntimeStatus.unknown()
      : generation = 0,
        phase = 'Off',
        owner = null,
        fdEpoch = 0,
        reason = '',
        engine = false,
        child = false,
        childLine = '';

  final int generation;
  final String phase;
  final PortalOwner? owner;
  final int fdEpoch;
  final String reason;

  /// Whether the engine's service holds a run.
  final bool engine;

  /// Whether the child says it is reading the tunnel.
  final bool child;

  /// The child's own last line, for a refusal that has to be shown as it happened.
  final String childLine;

  bool get active => phase == 'Active';

  bool get busy => phase == 'Starting' || phase == 'Stopping';

  bool get failed => phase == 'Failed';

  factory PortalRuntimeStatus.fromMap(Map<Object?, Object?> map) {
    final phase = (map['phase'] as String?) ?? 'Off';
    return PortalRuntimeStatus(
      generation: (map['generation'] as num?)?.toInt() ?? 0,
      phase: phase,
      owner: PortalOwner.of(map['owner'] as String?),
      fdEpoch: (map['fdEpoch'] as num?)?.toInt() ?? 0,
      reason: (map['reason'] as String?) ?? '',
      engine: map['engine'] == true,
      child: map['child'] == true,
      childLine: (map['childLine'] as String?) ?? '',
    );
  }

  @override
  String toString() =>
      'PortalRuntimeStatus(generation: $generation, phase: $phase, '
      'owner: ${owner?.label}, fdEpoch: $fdEpoch)';
}

/// The answer of one entry, and the record it left behind.
class PortalRuntimeAnswer {
  const PortalRuntimeAnswer({
    required this.ok,
    required this.status,
    this.cancelled = false,
    this.reason = '',
  });

  final bool ok;
  final bool cancelled;
  final String reason;
  final PortalRuntimeStatus status;

  bool get stale => cancelled;

  factory PortalRuntimeAnswer.fromMap(Map<Object?, Object?> map) {
    final state = map['state'];
    return PortalRuntimeAnswer(
      ok: map['ok'] == true,
      cancelled: map['cancelled'] == true,
      reason: (map['message'] as String?) ?? '',
      status: state is Map
          ? PortalRuntimeStatus.fromMap(state)
          : const PortalRuntimeStatus.unknown(),
    );
  }
}

/// The portal's one entry, from the app's side.
///
/// Every call is one transaction on the native side: a single mutex, one generation, and an
/// answer that arrives when the owner has acknowledged the tunnel. The app no longer starts
/// the service and the child in two calls it hopes are ordered — that pair *was* the race.
class PortalRuntime {
  PortalRuntime._();

  static final PortalRuntime instance = PortalRuntime._();

  static const _channel = MethodChannel('$packageName/portal');

  /// The newest record the app has seen. The switch screen reads it so a transaction in
  /// flight is shown as one instead of as an open or a closed portal.
  final ValueNotifier<PortalRuntimeStatus> status =
      ValueNotifier(const PortalRuntimeStatus.unknown());

  /// Builds the child's document for an entry that arrived without one.
  ///
  /// Quick Settings and Always-on can start the portal while no Flutter route is open; the
  /// document belongs to the profile and only this side can build it, so the native side
  /// asks for it inside the transaction.
  Future<String?> Function()? childConfigBuilder;

  void attach() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'prepareChildConfig':
          final builder = childConfigBuilder;
          if (builder == null) return null;
          try {
            return await builder();
          } catch (error) {
            commonPrint.log(
              'portal child config failed: $error',
              logLevel: LogLevel.warning,
            );
            return null;
          }
        default:
          return null;
      }
    });
  }

  Future<PortalRuntimeAnswer> open(
    PortalOwner owner, {
    String? config,
  }) async {
    return _invoke('open', {'owner': owner.label, 'config': ?config});
  }

  Future<PortalRuntimeAnswer> close({String reason = 'app'}) {
    return _invoke('close', {'reason': reason});
  }

  Future<PortalRuntimeAnswer> restart({String? config}) {
    return _invoke('restart', {'config': ?config});
  }

  /// A row tap while the child owns the tunnel: the same owner, a new document.
  Future<PortalRuntimeAnswer> startChild(String config) {
    return _invoke('startChild', {'config': config});
  }

  /// The switch's tap, for the record's own clock.
  ///
  /// One call, and the native side stamps the instant it arrives: the `phase=active` line in
  /// `portal-transitions.log` is written by the same hook that writes every transition, so no
  /// later step of the switch can get in front of it. A build without the channel is a
  /// desktop build, where nothing of this exists and nothing is measured.
  Future<void> beginSwitch({required String to}) async {
    try {
      await _channel.invokeMethod<void>('switchStart', {'to': to});
    } on MissingPluginException {
      // No portal runtime here: nothing to time.
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal switch clock failed: ${error.message}',
        logLevel: LogLevel.warning,
      );
    }
  }

  /// The screen's half of the measurement: the tap → a list with rows to draw.
  ///
  /// [detail] carries where the rows came from (`source=live|held|profile rows=<n>`), because
  /// they are three different facts and the line should not blur them.
  Future<void> noteSwitchTiming({
    required String phase,
    required int durationMs,
    String detail = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('switchTiming', {
        'phase': phase,
        'durationMs': durationMs,
        'detail': detail,
      });
    } on MissingPluginException {
      // No portal runtime here: nothing to write.
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal switch timing failed: ${error.message}',
        logLevel: LogLevel.warning,
      );
    }
  }

  /// One attempt at a mode's own feed, for the file adb can read.
  ///
  /// The count is Dart's — it describes this run's attempts, not the files on disk — so it is
  /// handed to the record rather than derived there. A build without the channel (desktop)
  /// has no `portal-transitions.log` and drops the line.
  Future<void> noteAvailability({
    required String feed,
    required String mode,
    required int attempts,
    required int limit,
    required String state,
    String reason = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('availabilityNote', {
        'feed': feed,
        'mode': mode,
        'attempts': attempts,
        'limit': limit,
        'state': state,
        'reason': reason,
      });
    } on MissingPluginException {
      // No portal runtime here: nothing to write.
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal availability note failed: ${error.message}',
        logLevel: LogLevel.warning,
      );
    }
  }

  /// A delay test that had to raise a core, for the transitions file.
  ///
  /// The test is a measurement, not a connection: [raised] names the core it raised (`child`,
  /// `engine` or `none`), [durationMs] is the whole test from the tap to the restored state,
  /// and [stoppedAfter] says whether that core was put back down — the audit line for "the
  /// portal ended where it started".
  Future<void> noteTest({
    required String mode,
    required String raised,
    required int durationMs,
    required bool stoppedAfter,
    String detail = '',
  }) async {
    try {
      await _channel.invokeMethod<void>('testNote', {
        'mode': mode,
        'raised': raised,
        'durationMs': durationMs,
        'stoppedAfter': stoppedAfter,
        'detail': detail,
      });
    } on MissingPluginException {
      // No portal runtime here: nothing to write.
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal test note failed: ${error.message}',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<PortalRuntimeStatus> refresh() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      final next = result == null
          ? const PortalRuntimeStatus.unknown()
          : PortalRuntimeStatus.fromMap(result);
      status.value = next;
      return next;
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal status failed: ${error.message}',
        logLevel: LogLevel.warning,
      );
      return status.value;
    } on MissingPluginException {
      return status.value;
    }
  }

  /// Runs one sweep in the measurement's own core slot.
  ///
  /// It is not the portal: no generation moves, the tunnel's instance is not touched, and the
  /// portal can stay open while the numbers come in. Answers the core's JSON verbatim; the
  /// caller parses it with [parseMeasured].
  Future<({bool ok, String message, String rows})> startMeasure({
    required String config,
    required String tags,
    required String url,
    int timeoutMs = 8000,
    int limit = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'measureStart',
        {
          'config': config,
          'tags': tags,
          'url': url,
          'timeoutMs': timeoutMs,
          'limit': limit,
        },
      );
      return (
        ok: result?['ok'] == true,
        message: '${result?['message'] ?? ''}',
        rows: '${result?['rows'] ?? ''}',
      );
    } on PlatformException catch (error) {
      return (ok: false, message: error.message ?? '$error', rows: '');
    } on MissingPluginException {
      return (ok: false, message: 'no child on this platform', rows: '');
    }
  }

  /// Closes the measurement instance. A failure is reported, not hidden: a core left behind
  /// would keep its listeners and its memory for the rest of the process.
  Future<bool> stopMeasure() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>('measureStop');
      return result?['ok'] == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<PortalRuntimeAnswer> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        arguments,
      );
      final answer = PortalRuntimeAnswer.fromMap(result ?? const {});
      status.value = answer.status;
      commonPrint.log(
        'portal $method: ok=${answer.ok} ${answer.status}'
        '${answer.reason.isEmpty ? '' : ' reason=${answer.reason}'}',
      );
      return answer;
    } on PlatformException catch (error) {
      commonPrint.log(
        'portal $method failed: ${error.message}',
        logLevel: LogLevel.error,
      );
      return PortalRuntimeAnswer(
        ok: false,
        reason: error.message ?? '$error',
        status: status.value,
      );
    } on MissingPluginException {
      // Desktop builds have no such channel: the engine alone is the portal there.
      return PortalRuntimeAnswer(
        ok: false,
        reason: 'the portal runtime is not available in this build',
        status: status.value,
      );
    }
  }
}

final portalRuntime = PortalRuntime.instance;
