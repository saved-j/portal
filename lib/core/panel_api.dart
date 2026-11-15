import 'dart:convert';

/// The panel's own API, asked the way its client apps ask it.
///
/// A subscription body carries nodes, not names: the readable name, the flag and the
/// description live in a JSON document the panel serves to clients that identify themselves
/// (Incy/Happ). The field names below were read out of the Incy APK's serializers:
/// `success`, `servers`, `serverName`, `serverFlag`, `description`, `address`, `port`.
class PanelApi {
  const PanelApi({required this.subscriptionUrl, required this.get});

  /// The subscription link the owner added; the panel resolves its own client request from
  /// the same link, so nothing else has to be configured.
  final String subscriptionUrl;

  /// A GET that returns the body as text, or null when the request failed.
  final Future<String?> Function(String url, Map<String, String> headers) get;

  /// The endpoint the panel's clients call, on the same host as the subscription.
  Uri get endpoint => Uri.parse(subscriptionUrl).replace(
        path: '/api/subscription/resolve',
        query: '',
      );

  /// Asks for the named server list.
  ///
  /// The client is identified by the user agent, exactly as a subscription download is;
  /// that is what makes the panel answer with the named JSON rather than an error.
  Future<PanelSubscription?> fetch({String userAgent = 'Incy/3.9.9'}) async {
    final body = await get(
      endpoint.toString(),
      {'User-Agent': userAgent, 'Accept': 'application/json'},
    );
    if (body == null || body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return PanelSubscription.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// What the panel says about one subscription: its servers and its traffic.
class PanelSubscription {
  const PanelSubscription({
    required this.servers,
    this.trafficLimit,
    this.trafficUsed,
    this.expiresAt,
  });

  final List<PanelServer> servers;
  final int? trafficLimit;
  final int? trafficUsed;
  final DateTime? expiresAt;

  static PanelSubscription fromJson(Map<String, dynamic> json) {
    final list = _firstList(json, ['servers', 'SERVERS', 'nodes', 'data']);
    return PanelSubscription(
      servers: [
        for (final item in list)
          if (item is Map) PanelServer.fromJson(Map<String, dynamic>.from(item)),
      ],
      trafficLimit: _firstInt(json, ['trafficLimit', 'total', 'limit', 'TRAFFIC_LIMIT']),
      trafficUsed: _firstInt(json, ['trafficUsed', 'used', 'TRAFFIC_USED']),
      expiresAt: _firstDate(json, ['expiresAt', 'expires', 'expire', 'Expires']),
    );
  }

  bool get isEmpty => servers.isEmpty;
}

/// One server as the panel names it.
class PanelServer {
  const PanelServer({
    required this.name,
    this.flag = '',
    this.description = '',
    this.address = '',
    this.port,
  });

  final String name;

  /// The emoji the panel puts in front of the name.
  final String flag;

  /// What the server is for: `Максимальная скорость`, `Глобальный ютуб`.
  final String description;
  final String address;
  final int? port;

  static PanelServer fromJson(Map<String, dynamic> json) => PanelServer(
        name: _firstString(json, ['serverName', 'SERVER_NAME', 'name', 'title']) ?? '',
        flag: _firstString(json, ['serverFlag', 'SERVER_FLAG', 'flag', 'emoji']) ?? '',
        description:
            _firstString(json, ['description', 'desc', 'subtitle', 'note']) ?? '',
        address: _firstString(json, ['address', 'host', 'server']) ?? '',
        port: _firstInt(json, ['port']),
      );

  /// `🇪🇪 Эстония · Максимальная скорость`, the row the owner reads.
  String get label {
    final head = flag.isEmpty ? name : '$flag $name';
    return description.isEmpty ? head : '$head · $description';
  }
}

List<Object?> _firstList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) return value;
  }
  return const [];
}

int? _firstInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

DateTime? _firstDate(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      final millis = value > 100000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}
