import 'dart:io';

import 'package:fl_clash/core/xray_config.dart';

/// Prints an Xray config for a sample node. Used to prove the converter's output is
/// accepted by the real binary: `xray run -test -c sample.json`.
void main(List<String> args) {
  final sample = <String, dynamic>{
    'name': 'sample-vless-ws-tls',
    'type': 'vless',
    'server': 'example.com',
    'port': 443,
    'uuid': '11111111-2222-3333-4444-555555555555',
    'network': 'ws',
    'tls': true,
    'servername': 'example.com',
    'ws-path': '/ray',
    'client-fingerprint': 'chrome',
  };
  stdout.writeln(xrayConfigJson(sample));
}
