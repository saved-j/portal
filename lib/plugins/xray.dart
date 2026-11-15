import 'dart:async';

import 'package:flutter/services.dart';

import '../common/constant.dart';

/// What the core actually answered.
///
/// A bare `ok` was the defect: a stop that returned before the child went, a plugin that
/// threw into a `catch` nothing read, and a start that was still waiting all read as
/// success at the call site. The outcome names which of those happened, and [message]
/// carries the child's own last line or the engine's complaint so the reason that reached
/// the log is the reason the owner is shown.
enum PortalCoreOutcome {
  /// The core acknowledged the step: the child took the tunnel, or the engine took the mode.
  ok,

  /// The step was interrupted by a newer request — a stop during a start, a newer pick.
  cancelled,

  /// This build cannot do it: no child on this platform, or nothing to answer for.
  unavailable,

  /// The core refused or failed, and [PortalCoreResult.message] says why.
  nativeError,
}

class PortalCoreResult {
  const PortalCoreResult(this.outcome, {this.message = ''});

  const PortalCoreResult.ok() : this(PortalCoreOutcome.ok);

  const PortalCoreResult.cancelled([String message = 'cancelled'])
      : this(PortalCoreOutcome.cancelled, message: message);

  const PortalCoreResult.unavailable(String message)
      : this(PortalCoreOutcome.unavailable, message: message);

  const PortalCoreResult.nativeError(String message)
      : this(PortalCoreOutcome.nativeError, message: message);

  final PortalCoreOutcome outcome;

  /// The child's last line, or the engine's own words; empty when there are none.
  final String message;

  bool get ok => outcome == PortalCoreOutcome.ok;

  bool get cancelled => outcome == PortalCoreOutcome.cancelled;

  /// One line fit to show: the message, or what the outcome means without one.
  String get reason {
    if (message.trim().isNotEmpty) return message.trim();
    return switch (outcome) {
      PortalCoreOutcome.ok => '',
      PortalCoreOutcome.cancelled => 'the step was cancelled',
      PortalCoreOutcome.unavailable => 'this build has no core for the portal',
      PortalCoreOutcome.nativeError => 'the core did not answer',
    };
  }

  @override
  String toString() => 'PortalCoreResult(${outcome.name}: $message)';
}

/// The Xray child process, driven from Dart.
///
/// The child runs on the simple portal's own tunnel: the Android service establishes it and
/// the plugin hands the descriptor over, so nothing here decides policy — it starts, reports
/// and stops. An answer is only `ok` when the child acknowledged the tunnel it was given.
class XrayCore {
  XrayCore._();

  static final XrayCore instance = XrayCore._();

  static const _channel = MethodChannel('$packageName/xray');

  /// Last line the child printed, kept so a failure can be shown as it happened.
  String lastLine = '';
  bool running = false;

  /// Starts the child on [config], which is one complete Xray document for the chosen node.
  ///
  /// The plugin replaces its entry point with the tunnel: the document's own inbounds are
  /// not used, and no socks bridge exists on the other side.
  Future<PortalCoreResult> start(String config) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('start', {
        'config': config,
      });
      final map = result?.cast<String, dynamic>() ?? const <String, dynamic>{};
      final ok = map['ok'] == true;
      running = ok;
      lastLine = (map['message'] as String?) ?? lastLine;
      if (ok) return const PortalCoreResult.ok();
      if (map['cancelled'] == true) {
        return PortalCoreResult.cancelled(lastLine);
      }
      return PortalCoreResult.nativeError(
        lastLine.isEmpty ? 'the portal core did not answer' : lastLine,
      );
    } on PlatformException catch (error) {
      lastLine = error.message ?? '$error';
      return PortalCoreResult.nativeError(lastLine);
    } on MissingPluginException {
      // Desktop builds have no such channel: the portal stays on the engine alone.
      lastLine = 'xray is not available in this build';
      return PortalCoreResult.unavailable(lastLine);
    }
  }

  Future<PortalCoreResult> stop() async {
    try {
      await _channel.invokeMethod('stop');
      running = false;
      return const PortalCoreResult.ok();
    } on PlatformException catch (error) {
      lastLine = error.message ?? '$error';
      // The process may well be gone; the answer is what the plugin said, not a guess.
      running = false;
      return PortalCoreResult.nativeError(lastLine);
    } on MissingPluginException {
      // Nothing to stop, which is the state the caller asked for.
      running = false;
      return const PortalCoreResult.ok();
    }
  }

  Future<Map<String, dynamic>> status() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('status');
      final map = result?.cast<String, dynamic>() ?? const <String, dynamic>{};
      running = map['running'] == true;
      lastLine = (map['lastLine'] as String?) ?? lastLine;
      return map;
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }
}
