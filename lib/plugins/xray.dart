import 'dart:async';

import 'package:flutter/services.dart';

import '../common/constant.dart';

/// The Xray child process, driven from Dart.
///
/// The engine keeps the tunnel; Xray owns the real node and is reached through the socks
/// outbound the configs already declare. Nothing here decides policy — it starts, reports,
/// and stops, so the switch stays a mode change rather than a rebuild.
class XrayCore {
  XrayCore._();

  static final XrayCore instance = XrayCore._();

  static const _channel = MethodChannel('$packageName/xray');

  /// Last line the child printed, kept so a failure can be shown as it happened.
  String lastLine = '';
  bool running = false;

  Future<Map<String, dynamic>> start(
    String config, {
    int port = 10808,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('start', {
        'config': config,
        'port': port,
      });
      final map = result?.cast<String, dynamic>() ?? const <String, dynamic>{};
      running = map['ok'] == true;
      lastLine = (map['message'] as String?) ?? lastLine;
      return map;
    } on PlatformException catch (error) {
      lastLine = error.message ?? '$error';
      return {'ok': false, 'message': lastLine};
    } on MissingPluginException {
      // Desktop builds have no such channel yet; the portal stays on the engine alone.
      lastLine = 'xray is not available in this build';
      return {'ok': false, 'message': lastLine};
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException catch (error) {
      lastLine = error.message ?? '$error';
    } on MissingPluginException {
      // Nothing to stop.
    }
    running = false;
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
