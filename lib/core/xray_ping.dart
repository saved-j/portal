import 'dart:async';
import 'dart:io';

/// A delay for servers the engine does not hold.
///
/// The simple portal is driven by the second core, and mihomo knows nothing about those
/// servers: every lookup in its delay table answers "timeout". So the row times the one
/// thing it can time honestly — a TCP connection to the server's own address, the same
/// handshake the tunnel performs before it can carry a byte.
///
/// It is not a proxy delay: it measures reachability and distance, not throughput through
/// the tunnel. The row says so by being a separate number, not by pretending to be mihomo's.
Future<int?> tcpPing(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (host.isEmpty || port <= 0) return null;
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    watch.stop();
    return watch.elapsedMilliseconds;
  } on SocketException {
    return null;
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }
}
