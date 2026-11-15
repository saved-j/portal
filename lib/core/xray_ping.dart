/// The delay number the simple portal's rows carry, and where it comes from.
///
/// The second core's nodes are invisible to the engine: mihomo holds none of them, so every
/// lookup in its delay table answers "timeout". What the child *can* do is carry a request — so
/// the number is a real request the child proxies, timed to its first response byte. That is
/// the tunnel's own end-to-end latency, measured by the only party that can measure it.
///
/// The previous version timed a TCP handshake to the node's own address from this process, and
/// it lied in a way no address filter could catch: with the child holding a tun, this app's own
/// sockets are routed into it, the core accepts the connection locally and answers in 3–4 ms —
/// to Estonia, against a real address. A number that never left the phone is worse than a dash,
/// so the handshake is gone. What is left cannot be answered by the phone: a request to a host
/// this app does not run has to leave through the node to come back at all.
library;

import 'dart:async';
import 'dart:io';

/// Why a row has a number, or does not.
enum PortalDelayNote {
  /// The first response byte came back through the child: this is the tunnel's own latency.
  measured,

  /// No child is carrying traffic, so there is no tunnel to measure through.
  noTunnel,

  /// Nothing to request: no URL, or a URL without a host.
  noUrl,

  /// No byte came back within the deadline.
  timeout,

  /// The connection was refused, the route was unreachable, or the request raised.
  failed,
}

/// One measurement through the running portal, and what it timed.
class PortalDelay {
  const PortalDelay({
    required this.url,
    required this.note,
    this.ms,
  });

  final String url;
  final PortalDelayNote note;
  final int? ms;

  bool get answered => note == PortalDelayNote.measured && ms != null;

  /// The last path segment, which is what a log line names: `generate_204`.
  String get target {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.last.isEmpty) return uri.host;
    return segments.last;
  }

  /// `generate_204 214 ms`, or the reason there is no number.
  String describe() => switch (note) {
        PortalDelayNote.measured => '$target $ms ms',
        PortalDelayNote.noTunnel => 'no tunnel is carrying traffic, no number',
        PortalDelayNote.noUrl => 'no test url to request',
        PortalDelayNote.timeout => '$target timed out, no number',
        PortalDelayNote.failed => '$target failed, no number',
      };
}

/// Times a request the running child carries, from the first byte of the connection attempt.
///
/// The clock starts before the connection: the round trip that matters includes the tunnel's
/// own hand-over, so a number started after `connect` would flatter the node. The request is a
/// `GET` with `Connection: close` and only the first byte is read — a 204 has no body, and
/// reading it would add throughput to a latency figure.
///
/// [url] is the app's own test URL (`appSettingProvider.testUrl`), the same one the engine's
/// URLTEST uses, so a number from the portal and a number from the engine are comparable.
Future<PortalDelay> probeThroughPortal(
  String url, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return PortalDelay(url: url, note: PortalDelayNote.noUrl);
  }
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final path = uri.path.isEmpty ? '/' : uri.path;
  final request = 'GET $path HTTP/1.1\r\n'
      'Host: ${uri.host}\r\n'
      'User-Agent: portal-delay\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n';
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    // The name, never a stored address: the tunnel's own DNS answers it and the node carries
    // the connection, which is the whole point of measuring this way.
    socket = uri.scheme == 'https'
        ? await SecureSocket.connect(uri.host, port, timeout: timeout)
        : await Socket.connect(uri.host, port, timeout: timeout);
    socket.write(request);
    await socket.flush();
    final first = await socket.first.timeout(timeout);
    watch.stop();
    if (first.isEmpty) {
      return PortalDelay(url: url, note: PortalDelayNote.failed);
    }
    return PortalDelay(
      url: url,
      note: PortalDelayNote.measured,
      ms: watch.elapsedMilliseconds,
    );
  } on TimeoutException {
    return PortalDelay(url: url, note: PortalDelayNote.timeout);
  } on SocketException {
    return PortalDelay(url: url, note: PortalDelayNote.failed);
  } catch (_) {
    return PortalDelay(url: url, note: PortalDelayNote.failed);
  } finally {
    watch.stop();
    socket?.destroy();
  }
}
