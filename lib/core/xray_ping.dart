import 'dart:async';
import 'dart:io';

/// Why a row has a number, or does not.
enum TcpPingNote {
  /// A real address answered the handshake: this is the node's own round trip.
  measured,

  /// Nothing to measure: no host, no port.
  noAddress,

  /// The name resolved only to an address the tunnel owns (fake-IP or the tun's own gateway),
  /// or the profile named one. Handshaking there measures the phone's own listener.
  fakeAddress,

  /// The name did not resolve within the resolve deadline.
  unresolved,

  /// The handshake did not complete within the deadline.
  timeout,

  /// The handshake was refused or the route was unreachable.
  unreachable,
}

/// One honest measurement of one server, and the address it was taken against.
///
/// [ms] is null whenever the measurement is not a fact about the node — never a fabricated
/// number, and never the duration of a handshake that never left the phone.
class TcpPing {
  const TcpPing({
    required this.host,
    required this.port,
    required this.note,
    this.address,
    this.looked = const [],
    this.ms,
  });

  final String host;
  final int port;
  final TcpPingNote note;

  /// The address the handshake was timed against, when there was one.
  final InternetAddress? address;

  /// What the name resolved to, fake addresses included: the reason a dash is a dash.
  final List<InternetAddress> looked;

  final int? ms;

  bool get answered => ms != null && ms! >= 0;

  /// `host:port → 185.155.222.6 214 ms`, or the reason there is no number.
  String describe() {
    final where = host.isEmpty ? '' : '$host:$port';
    switch (note) {
      case TcpPingNote.measured:
        return '$where → ${address?.address} $ms ms';
      case TcpPingNote.fakeAddress:
        final listed = looked.isEmpty
            ? (address?.address ?? '')
            : looked.map((item) => item.address).join(',');
        return "$where → $listed is the tunnel's own address, no number";
      case TcpPingNote.unresolved:
        return '$where → no address, no number';
      case TcpPingNote.timeout:
        return '$where → ${address?.address} timed out, no number';
      case TcpPingNote.unreachable:
        return '$where → ${address?.address} unreachable, no number';
      case TcpPingNote.noAddress:
        return 'no address to measure';
    }
  }
}

/// Whether [address] belongs to the tunnel rather than to a server.
///
/// With a tun up, a name the engine answers for resolves to its fake-IP (`198.18.0.0/15`, the
/// range mihomo and Xray's fake DNS both use), and the tun's own gateway and resolver sit
/// inside it. A TCP handshake to one of those completes against the core's local listener,
/// which is how a row read 5 ms to Finland from China: the number was the phone's own loop.
/// Loopback, the unspecified address and link-local are refused for the same reason — none of
/// them is a server a subscription sells, and all of them answer instantly.
bool isTunnelOwnedAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    if (raw.length != 16) return false;
    final loopback = raw.take(15).every((byte) => byte == 0) && raw.last == 1;
    final unspecified = raw.every((byte) => byte == 0);
    return loopback || unspecified;
  }
  if (raw.length != 4) return false;
  final a = raw[0];
  final b = raw[1];
  // 0.0.0.0 — an unspecified host is not an address to shake hands with.
  if (a == 0) return true;
  // 127.0.0.0/8 — loopback: the local listener answers instantly.
  if (a == 127) return true;
  // 198.18.0.0/15 — fake-IP, and the tun's gateway 198.18.0.1 / resolver 198.18.0.2.
  if (a == 198 && (b == 18 || b == 19)) return true;
  // 169.254.0.0/16 — link-local.
  if (a == 169 && b == 254) return true;
  return false;
}

InternetAddress? _literal(String host) {
  final trimmed = host.trim();
  if (trimmed.isEmpty) return null;
  // `InternetAddress.tryParse` accepts only a numeric literal, which is exactly the case
  // where no lookup may happen at all.
  return InternetAddress.tryParse(trimmed);
}

/// Times a TCP handshake to [host]: a delay for servers the engine does not hold.
///
/// The simple portal is driven by the second core, and mihomo knows nothing about those
/// servers: every lookup in its delay table answers "timeout". So the row times the one thing
/// it can time honestly — a TCP connection to the server's own address, the same handshake the
/// tunnel performs before it can carry a byte.
///
/// It is not a proxy delay: it measures reachability and distance, not throughput through the
/// tunnel. What it must never measure is the tunnel itself. The name is resolved here, a
/// fake-IP or the tun's gateway is refused instead of timed (see [isTunnelOwnedAddress]), and
/// the handshake is opened against the resolved address so a second lookup cannot answer with
/// a different one. A timeout, an unreachable route or a fake address is a dash on the row —
/// never a number.
Future<TcpPing> probeTcp(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
  Duration resolveTimeout = const Duration(seconds: 2),
}) async {
  if (host.trim().isEmpty || port <= 0) {
    return TcpPing(host: host, port: port, note: TcpPingNote.noAddress);
  }
  InternetAddress? address = _literal(host);
  if (address == null) {
    List<InternetAddress> found;
    try {
      found = await InternetAddress.lookup(
        host.trim(),
      ).timeout(resolveTimeout);
    } on TimeoutException {
      return TcpPing(host: host, port: port, note: TcpPingNote.unresolved);
    } on SocketException {
      return TcpPing(host: host, port: port, note: TcpPingNote.unresolved);
    } catch (_) {
      return TcpPing(host: host, port: port, note: TcpPingNote.unresolved);
    }
    if (found.isEmpty) {
      return TcpPing(host: host, port: port, note: TcpPingNote.unresolved);
    }
    final real = [
      for (final item in found)
        if (!isTunnelOwnedAddress(item)) item,
    ];
    if (real.isEmpty) {
      return TcpPing(
        host: host,
        port: port,
        note: TcpPingNote.fakeAddress,
        looked: found,
        address: found.first,
      );
    }
    address = real.first;
  } else if (isTunnelOwnedAddress(address)) {
    return TcpPing(
      host: host,
      port: port,
      note: TcpPingNote.fakeAddress,
      looked: [address],
      address: address,
    );
  }
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await Socket.connect(address, port, timeout: timeout);
    watch.stop();
    return TcpPing(
      host: host,
      port: port,
      note: TcpPingNote.measured,
      address: address,
      looked: [address],
      ms: watch.elapsedMilliseconds,
    );
  } on TimeoutException {
    return TcpPing(
      host: host,
      port: port,
      note: TcpPingNote.timeout,
      address: address,
      looked: [address],
    );
  } on SocketException {
    return TcpPing(
      host: host,
      port: port,
      note: TcpPingNote.unreachable,
      address: address,
      looked: [address],
    );
  } catch (_) {
    return TcpPing(
      host: host,
      port: port,
      note: TcpPingNote.unreachable,
      address: address,
      looked: [address],
    );
  } finally {
    socket?.destroy();
  }
}

/// The number alone, for a caller that only draws a row. Null is the dash.
Future<int?> tcpPing(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
}) async => (await probeTcp(host, port, timeout: timeout)).ms;
