import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/subscription_availability.dart';
import 'package:fl_clash/core/panel_api.dart';
import 'package:fl_clash/core/proxy_endpoints.dart';
import 'package:fl_clash/core/subscription_formats.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'clash_config.dart';
import 'provider_headers.dart';

part 'generated/profile.freezed.dart';
part 'generated/profile.g.dart';

typedef ValidateConfig =
    Future<String> Function(String path, String ageSecretKey);

/// Past DateTime's last moment, 8.64e15 ms, an expiry would throw where shown.
const _maxExpireSeconds = 8640000000000;

int _validExpire(num seconds) =>
    seconds > 0 && seconds <= _maxExpireSeconds ? seconds.toInt() : 0;

@freezed
abstract class SubscriptionInfo with _$SubscriptionInfo {
  const factory SubscriptionInfo({
    @Default(0) int upload,
    @Default(0) int download,
    @Default(0) int total,
    @JsonKey(fromJson: _validExpire) @Default(0) int expire,
  }) = _SubscriptionInfo;

  factory SubscriptionInfo.fromJson(Map<String, Object?> json) =>
      _$SubscriptionInfoFromJson(json);

  factory SubscriptionInfo.formHString(String? info) {
    if (info == null) return const SubscriptionInfo();
    final Map<String, int> map = {};
    for (final field in info.split(';')) {
      final separator = field.indexOf('=');
      if (separator == -1) continue;
      final value = _parseCount(field.substring(separator + 1).trim());
      if (value != null) {
        map[field.substring(0, separator).trim().toLowerCase()] = value;
      }
    }
    return SubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: _validExpire(map['expire'] ?? 0),
    );
  }

  static int? _parseCount(String value) {
    final count = int.tryParse(value);
    if (count != null) return count;
    final decimal = double.tryParse(value);
    return decimal != null && decimal.isFinite ? decimal.truncate() : null;
  }
}

extension SubscriptionInfoExt on SubscriptionInfo {
  double? get usage =>
      total > 0 ? ((upload + download) / total).clamp(0.0, 1.0) : null;

  DateTime? get expireDate =>
      expire > 0 ? DateTime.fromMillisecondsSinceEpoch(expire * 1000) : null;
}

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required int id,
    @Default(ProfileType.file) ProfileType type,
    @Default('') String label,
    String? currentGroupName,
    @Default('') String url,
    @Default('') String ageSecretKey,
    DateTime? lastUpdateDate,
    required Duration autoUpdateDuration,
    SubscriptionInfo? subscriptionInfo,
    @Default(true) bool autoUpdate,
    @Default({}) Map<String, String> selectedMap,
    @Default({}) Set<String> unfoldSet,
    @Default(ExtendType.standard) ExtendType extendType,
    int? scriptId,
    String? matchTarget,
    int? order,
    @Default(ProfileOverrides())
    @JsonKey(fromJson: ProfileOverrides.safeFromJson)
    ProfileOverrides overrides,

    /// The subscription's response headers, lower-cased, see [providerHeaderNames].
    @Default({}) Map<String, String> providerHeaders,

    /// Whether downloads carry the device id headers a panel binds by.
    @Default(true) bool sendDeviceHeaders,
  }) = _Profile;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);

  factory Profile.normal({
    String? label,
    String url = '',
    bool sendDeviceHeaders = true,
  }) {
    final id = snowflake.id;
    return Profile(
      type: url.isEmpty ? ProfileType.file : ProfileType.url,
      label: label ?? '',
      url: url,
      id: id,
      autoUpdateDuration: defaultUpdateDuration,
      sendDeviceHeaders: sendDeviceHeaders,
    );
  }

  factory Profile.custom({String? label}) {
    return Profile(
      id: snowflake.id,
      type: ProfileType.custom,
      label: label ?? '',
      lastUpdateDate: DateTime.now(),
      autoUpdate: false,
      autoUpdateDuration: defaultUpdateDuration,
    );
  }
}

/// A profile leaving out one of the global rules its extension would add.
@freezed
abstract class DisabledRule with _$DisabledRule {
  const factory DisabledRule({required int profileId, required int ruleId}) =
      _DisabledRule;
}

extension ProfilesExt on List<Profile> {
  Profile? getProfile(int? profileId) {
    final index = indexWhere((profile) => profile.id == profileId);
    return index == -1 ? null : this[index];
  }

  Profile optimizeLabel(Profile profile) {
    return profile.copyWith(
      label: uniqueLabelFor(
        profile.label,
        fallback: profile.defaultLabel,
        taken: (label) =>
            any((item) => item.label == label && item.id != profile.id),
      ),
    );
  }
}

extension ProfileExtension on Profile {
  /// The name a person reads: the panel's title without its status sentence.
  ///
  /// Panels pack `portal-connect Статус Active 163.76 GiB | 0` into the title header, and
  /// that becomes the profile's label; showing it whole made the header and the card look
  /// broken. One getter cleans it for every screen at once.
  String get realLabel =>
      label.takeFirstValid([headers.displayName, defaultLabel]);

  String get defaultLabel => url.webUri?.host ?? id.toString();

  String get exportFileName {
    final label = realLabel;
    final lower = label.toLowerCase();
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return label;
    }
    return '$label.yaml';
  }

  String get updatingKey => 'profile_$id';

  // In milliseconds: an interval a panel sent may pass DateTime's last moment.
  bool? get isAutoUpdateDue => switch (lastUpdateDate) {
    null => null,
    final last =>
      last.millisecondsSinceEpoch + autoUpdateDuration.inMilliseconds <
          DateTime.now().millisecondsSinceEpoch,
  };

  /// The database keeps [lastUpdateDate] only to the second.
  ({
    String url,
    String ageSecretKey,
    bool sendDeviceHeaders,
    int? lastUpdateSeconds,
  })
  get fileRevision => (
    url: url,
    ageSecretKey: ageSecretKey,
    sendDeviceHeaders: sendDeviceHeaders,
    lastUpdateSeconds: switch (lastUpdateDate) {
      final date? => date.millisecondsSinceEpoch ~/ 1000,
      null => null,
    },
  );

  Future<bool> get isMissingFile async =>
      type == ProfileType.url && !await (await _getFile(false)).exists();

  Future<File> _getFile([bool autoCreate = true]) async {
    final path = await appPath.getProfilePath(id.toString());
    final file = File(path);
    final isExists = await file.exists();
    if (!isExists && autoCreate) {
      return file.create(recursive: true);
    }
    return file;
  }

  Future<File> get file async {
    return _getFile();
  }

  /// Downloads from [url], then from the panel's fallback hosts in order; a
  /// hard failure of [url] moves the profile onto the host that answered.
  Future<Profile> update({
    required ValidateConfig validate,
    SubscriptionFetch? fetch,
    DeviceHeaders? deviceHeaders,
    bool Function()? isCurrent,
  }) async {
    fetch ??= request.getFileResponseForUrl;
    final sent = sendDeviceHeaders
        ? await (deviceHeaders ?? deviceIdentity.headers)()
        : const <String, String>{};
    final Object firstError;
    final StackTrace firstTrace;
    try {
      return await _updateFrom(
        url,
        validate,
        fetch,
        sent,
        downloadTimeoutDuration,
        isCurrent,
      );
    } on ProfileUpdateSupersededException {
      rethrow;
    } catch (error, trace) {
      firstError = error;
      firstTrace = trace;
    }
    final fallbacks = headers.fallbackUrlsOf(Uri.tryParse(url) ?? Uri());
    if (fallbacks.isEmpty) {
      Error.throwWithStackTrace(firstError, firstTrace);
    }
    final failure = hostFailureOf(firstError);
    commonPrint.log(
      'subscription host failed (${failure.name}): ${compactError(firstError)}',
      logLevel: LogLevel.warning,
    );
    for (final fallback in fallbacks) {
      try {
        final updated = await _updateFrom(
          fallback.toString(),
          validate,
          fetch,
          sent,
          fallbackTimeoutDuration,
          isCurrent,
        );
        commonPrint.log(
          'subscription served by ${fallback.host}'
          '${failure == HostFailure.hard ? ', profile moved there' : ''}',
        );
        return failure == HostFailure.hard
            ? updated.copyWith(url: fallback.toString())
            : updated;
      } on ProfileUpdateSupersededException {
        rethrow;
      } catch (error) {
        commonPrint.log(
          'fallback ${fallback.host} failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
      }
    }
    Error.throwWithStackTrace(firstError, firstTrace);
  }

  Future<Profile> _updateFrom(
    String url,
    ValidateConfig validate,
    SubscriptionFetch fetch,
    Map<String, String> headers,
    Duration timeout,
    bool Function()? isCurrent,
  ) async {
    final response = await fetch(url, timeout: timeout, headers: headers);
    // The same link answers differently per client, so the second format is asked for
    // separately. A failure here must not fail the profile: the panel may simply not
    // serve one, and that is a red light, not an error.
    final xray = await _fetchXrayBody(url, fetch, timeout);
    final disposition = response.headers.value('content-disposition');
    final userinfo = response.headers.value('subscription-userinfo');
    final providerHeaders = providerHeadersOf(response.headers.map);
    // The row can only show traffic and an expiry if the panel sends them; this line says
    // which of the two shapes arrived, since a missing header and a mis-parsed one look the
    // same from the screen. The values themselves are the account's credentials — the line
    // keeps their shape and their length, never their content.
    commonPrint.log(
      'sub headers: userinfo=${userinfo == null ? 'absent' : 'present(${userinfo.length})'} '
      'provider=${providerHeaders.entries.map((e) => '${e.key}:${e.value.length}').join(', ')}',
    );
    for (final entry in providerHeaders.entries) {
      if (!entry.value.startsWith('base64:')) continue;
      final decoded = _decodeProviderBase64(entry.value);
      if (decoded != null) {
        commonPrint.log('sub header ${entry.key} decoded: ${decoded.length} chars');
      }
    }
    // The panel names its servers behind its own API, so the same link is asked once for the
    // names. A failure here is normal (a panel without that endpoint) and changes nothing.
    unawaited(_probePanelNames(url));
    return copyWith(
      label: label.takeFirstValid([
        ProviderHeaders(providerHeaders).title,
        getFileNameForDisposition(disposition),
        defaultLabel,
      ]),
      subscriptionInfo: SubscriptionInfo.formHString(userinfo),
      providerHeaders: providerHeaders,
      autoUpdateDuration:
          ProviderHeaders(providerHeaders).updateInterval ?? autoUpdateDuration,
    ).saveFile(
      await decompressDownload(response.data ?? Uint8List(0)),
      validate: _guardEmptyBody(validate),
      isCurrent: isCurrent,
      xrayBody: xray,
    );
  }

  /// The publishing rename is sync, so nothing runs between [isCurrent] and it.
  Future<Profile> saveFile(
    Uint8List bytes, {
    required ValidateConfig validate,
    bool Function()? isCurrent,
    Uint8List? xrayBody,
  }) async {
    final target = await _getFile(false);
    // The engine never reveals addresses, so remember them while the body is here: this is
    // what lets the server row time a TCP handshake later, with no engine involved.
    final endpoints = parseProxyEndpoints(
      utf8.decode(bytes, allowMalformed: true),
    );
    unawaited(saveProxyEndpoints(target.path, endpoints));
    final staging = File('${target.path}.$uniqueId.tmp');
    try {
      await staging.safeWriteAsBytes(bytes);
      final message = await validate(staging.path, ageSecretKey);
      if (message.isNotEmpty) {
        throw MessageException(message);
      }
      if (isCurrent != null && !isCurrent()) {
        throw const ProfileUpdateSupersededException();
      }
      staging.renameSync(target.path);
      // Only a body that parsed replaces the one on disk. A panel that answers 200 with an
      // error page, or a list that decodes to nothing, must never cost the owner a working
      // subscription: the lights go dim, the old file stays.
      await _saveXraySibling(target, xrayBody);
    } catch (_) {
      await staging.safeDelete();
      rethrow;
    }
    return copyWith(lastUpdateDate: DateTime.now());
  }

  /// Whether [body] is something the second core could actually run.
  ///
  /// Two shapes count: a list of share links, and a ready config the panel wrote itself
  /// (Happ and Incy are served the latter). Anything else — an error page, a broken list —
  /// must not replace what is already on disk.
  static bool _usableXrayBody(Uint8List? body) {
    if (body == null || body.isEmpty) return false;
    final text = utf8.decode(body, allowMalformed: true);
    if (decodeClientConfig(text) != null) return true;
    return parseShareLinks(text).isNotEmpty;
  }


  /// Asks the panel's own API for the names it gives its servers, and logs what arrives.
  ///
  /// This is how the panel's own clients do it: same link, client identified by the user
  /// agent, JSON back. A failure changes nothing — the app still has its nodes.
  static Future<PanelSubscription?> _probePanelNames(String subscriptionUrl) async {
    try {
      final api = PanelApi(
        subscriptionUrl: subscriptionUrl,
        get: (url, headers) async {
          final response = await request.getTextResponseForUrl(url, headers: headers);
          return response.data;
        },
      );
      final panel = await api.fetch();
      if (panel == null) {
        commonPrint.log('panel resolve: no json at ${api.endpoint}');
        return null;
      }
      commonPrint.log(
        'panel resolve: ${panel.servers.length} servers, '
        'first=${panel.servers.take(3).map((s) => s.label).join(' | ')}',
      );
      return panel;
    } catch (error) {
      commonPrint.log('panel resolve failed: ${compactError(error)}');
      return null;
    }
  }
  /// The second core's body lives beside the profile, named after it.
  ///
  /// It is a sibling rather than a field in the profile record because it is a large
  /// blob that only the Xray path reads; the record stays small enough to keep in memory.
  Future<void> _saveXraySibling(File profileFile, Uint8List? body) async {
    final sibling = File('${profileFile.path}.xray.txt');
    if (!_usableXrayBody(body)) {
      // Nothing usable arrived. The old body is kept: a subscription that worked five
      // minutes ago beats an empty file, and the lights already say what is missing.
      return;
    }
    await sibling.safeWriteAsBytes(body!);
  }

  /// True when this profile has a body for the second core, without reading it whole.
  Future<bool> hasXrayFormat() async {
    final file = File(await _xraySiblingPath);
    return await file.exists() && await file.length() > 20;
  }

  /// The second core's body as text, or null when the panel never served one.
  Future<String?> readXrayFormat() async {
    final file = File(await _xraySiblingPath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<String> get _xraySiblingPath async =>
      '${await appPath.getProfilePath(id.toString())}.xray.txt';
  /// Refuses to hand an empty download to the validator, which would otherwise accept a
  /// file that has nothing in it and replace a working config with a blank one.
  static ValidateConfig _guardEmptyBody(ValidateConfig validate) {
    return (path, key) async {
      final file = File(path);
      if (!await file.exists() || await file.length() < 16) {
        return 'empty response';
      }
      return validate(path, key);
    };
  }

  /// Asks the same link for the second core's format.
  ///
  /// Which client name a panel accepts is its decision, and it answers 502 to the rest, so
  /// the candidates are asked in turn until one returns nodes. The first success wins and
  /// the rest are not tried, which keeps a working panel to a single extra request.
  Future<Uint8List?> _fetchXrayBody(
    String url,
    SubscriptionFetch fetch,
    Duration timeout,
  ) async {
    for (final agent in xrayUserAgentCandidates) {
      try {
        final response = await fetch(
          url,
          timeout: timeout,
          headers: {'User-Agent': agent},
        );
        final body = response.data;
        final text = body == null ? '' : utf8.decode(body, allowMalformed: true);
        final format = detectFormat(text);
        commonPrint.log(
          'xray probe [$agent]: http=${response.statusCode} '
          'bytes=${body?.length ?? 0} format=${format?.name ?? 'none'} '
          'head=${text.length > 120 ? text.substring(0, 120).replaceAll('\n', ' ') : text}',
        );
        if (body != null && format == SubscriptionFormat.xray) return body;
      } catch (error) {
        commonPrint.log('xray probe [$agent]: ${compactError(error)}');
      }
    }
    return null;
  }
}

typedef SubscriptionFetch =
    Future<Response<Uint8List>> Function(
      String url, {
      Duration timeout,
      Map<String, String> headers,
    });

typedef DeviceHeaders = Future<Map<String, String>> Function();

const fallbackTimeoutDuration = Duration(seconds: 10);

const providerHeaderNames = {
  'announce',
  'support-url',
  'profile-title',
  'profile-web-page-url',
  'profile-update-interval',
  'x-hwid-max-devices-reached',
  'x-hwid-not-supported',
};

const providerHeaderPrefix = 'flclashx-';

/// The subscription's own headers, keys lower-cased, first value kept.
Map<String, String> providerHeadersOf(Map<String, List<String>> headers) {
  return {
    for (final MapEntry(:key, :value) in headers.entries)
      if (value.isNotEmpty)
        if (providerHeaderNames.contains(key.toLowerCase()) ||
            key.toLowerCase().startsWith(providerHeaderPrefix))
          key.toLowerCase(): value.first,
  };
}

/// The panel base64-encodes some headers so they survive any transport; this decodes one.
String? _decodeProviderBase64(String value) {
  try {
    final payload = value.substring('base64:'.length).trim();
    return utf8.decode(base64Decode(base64Url.normalize(payload)));
  } catch (_) {
    return null;
  }
}
