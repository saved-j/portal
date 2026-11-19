import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../common/path.dart';
import '../../common/print.dart';

/// The Xray child on a desktop: a process, not a library.
///
/// On Android the child runs inside this app's process and the service hands it the tunnel's
/// descriptor. A desktop has no such handover — the tunnel belongs to the helper's TUN and to
/// the engine that reads it — so the same role is played by a separate process: Xray listens
/// on a loopback socks inlet with the node the owner picked, and the engine sends the whole
/// tunnel into that inlet. The transport work is the child's, the TUN, DNS and rules stay the
/// engine's, which is how a desktop can carry both cores at once.
///
/// The port is process state, not a setting: it lives as long as the child does, and the
/// bridge config is built from it.
class DesktopXrayChild {
  DesktopXrayChild._();

  static Process? _process;
  static int? _port;
  static String _document = '';

  /// The loopback port the child listens on, null while it is not running.
  static int? get port => _port;

  static bool get running => _process != null && _port != null;

  /// The document the child was started with, so a restart can be skipped when nothing changed.
  static String get document => _document;

  /// One measurement sweep, run by the core itself.
  ///
  /// The sweep is the phone's: the same Go code that answers `XrayMeasure` inside libxray is
  /// built into this binary as the `measure` subcommand, so a desktop row and a phone row are
  /// produced by one implementation — the core dials each outbound with its own tag and says
  /// how long the request took. Nothing listens on loopback, and the tunnel's own instance is
  /// untouched, which is what lets a sweep run while the portal is up.
  ///
  /// Returns the rows as the core wrote them, or an error message.
  static Future<({bool ok, String message, String rows})> measure({
    required String config,
    required List<String> tags,
    required String url,
    int timeoutMs = 8000,
  }) async {
    final binary = await _binaryPath();
    if (binary == null) {
      return (ok: false, message: 'the xray binary is missing', rows: '');
    }
    final file = File('${await appPath.homeDirPath}/xray-measure.json');
    try {
      await file.writeAsString(config);
    } catch (error) {
      return (ok: false, message: '$error', rows: '');
    }
    try {
      final result = await Process.run(binary.path, [
        'measure',
        file.path,
        url,
        '$timeoutMs',
        jsonEncode(tags),
      ], workingDirectory: binary.parent.path);
      final out = '${result.stdout}'.trim();
      if (result.exitCode != 0 || !out.startsWith('{')) {
        return (
          ok: false,
          message: out.isEmpty ? 'measure exited with ${result.exitCode}' : out,
          rows: '',
        );
      }
      return (ok: true, message: '', rows: out);
    } catch (error) {
      return (ok: false, message: '$error', rows: '');
    }
  }

  /// Starts the child on [document], a full Xray config for every node of the subscription.
  ///
  /// The config is the engine-format document with one thing added: a socks inbound on a free
  /// loopback port. Everything else — every node, the selected one, the observatory — is what
  /// the Android child runs, so both platforms carry the same document.
  static Future<bool> start(String document) async {
    if (running && document == _document) return true;
    await stop();
    final binary = await _binaryPath();
    if (binary == null) {
      commonPrint.log('desktop child: the xray binary is missing');
      return false;
    }
    final freePort = await _freePort();
    final config = _withSocksInbound(document, freePort);
    if (config == null) {
      commonPrint.log('desktop child: the document is not a JSON object');
      return false;
    }
    final file = File('${await appPath.homeDirPath}/xray-desktop.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
    final process = await Process.start(binary.path, [
      '-c',
      file.path,
    ], workingDirectory: binary.parent.path);
    _process = process;
    _port = freePort;
    _document = document;
    // The child's own lines go to the app log: a node that cannot be reached is the child's
    // answer, and it is the only place the reason exists.
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => commonPrint.log('xray: $line'));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => commonPrint.log('xray: $line'));
    final opened = await _waitForPort(freePort);
    if (!opened) {
      commonPrint.log('desktop child: the inlet did not open on $freePort');
      await stop();
      return false;
    }
    commonPrint.log('desktop child: listening on 127.0.0.1:$freePort');
    return true;
  }

  static Future<void> stop() async {
    final process = _process;
    _process = null;
    _port = null;
    _document = '';
    if (process == null) return;
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// The engine document for a desktop simple portal: everything into the child's inlet.
  ///
  /// One proxy, one group, one rule. The engine keeps the tunnel, the DNS and the routes; the
  /// only outbound it knows is the child, so nothing of the network mode can leak into this
  /// mode's traffic.
  static String bridgeProfile(int inletPort, {int? mixedPort}) {
    final buffer = StringBuffer()
      ..writeln('mode: rule')
      ..writeln('log-level: warning')
      ..writeln('ipv6: false')
      ..writeln('proxies:')
      ..writeln('  - name: portal-xray')
      ..writeln('    type: socks5')
      ..writeln('    server: 127.0.0.1')
      ..writeln('    port: $inletPort')
      ..writeln('    udp: true')
      ..writeln('proxy-groups:')
      ..writeln('  - name: PORTAL')
      ..writeln('    type: select')
      ..writeln('    proxies:')
      ..writeln('      - portal-xray')
      ..writeln('rules:')
      ..writeln('  - DOMAIN-SUFFIX,local,DIRECT')
      ..writeln('  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve')
      ..writeln('  - MATCH,PORTAL');
    if (mixedPort != null && mixedPort > 0) {
      buffer
        ..writeln('mixed-port: $mixedPort');
    }
    return buffer.toString();
  }

  static Map<String, Object?>? _withSocksInbound(
    String document,
    int port,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(document);
    } catch (error) {
      commonPrint.log('desktop child: cannot read the document: $compactError(error)');
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final inbounds = <Object?>[
      {
        'listen': '127.0.0.1',
        'port': port,
        'protocol': 'socks',
        'settings': {'udp': true},
        'tag': 'portal-inlet',
      },
    ];
    return {...decoded, 'inbounds': inbounds};
  }

  static Future<File?> _binaryPath() async {
    final name = Platform.isWindows ? 'xray.exe' : 'xray';
    final beside = File('${await appPath.homeDirPath}/$name');
    if (await beside.exists()) return beside;
    final executable = File(Platform.resolvedExecutable);
    final bundled = File('${executable.parent.path}/$name');
    if (await bundled.exists()) return bundled;
    return null;
  }

  static Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<bool> _waitForPort(int port) async {
    for (var attempt = 0; attempt < 40; attempt++) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 200),
        );
        socket.destroy();
        return true;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    return false;
  }
}
