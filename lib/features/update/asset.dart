import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const updateHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

/// The largest download the app accepts, whatever the release claims.
const updateSizeCeiling = 512 * 1024 * 1024;

/// How this copy of the app was installed, which decides what replaces it.
enum UpdateInstallKind {
  android,
  windows,
  macos,
  appImage,
  deb,
  rpm,
  packageManager,
  unsupported,
}

enum UpdateErrorKind {
  noAsset,
  noChecksum,
  untrustedHost,
  tooLarge,
  incomplete,
  network,
  checksumMismatch,
  identityMismatch,
  notNewer,
  busy,
  safeMode,
  installPermission,
  installFailed,
}

final class UpdateException implements Exception {
  final UpdateErrorKind kind;
  final String? detail;

  const UpdateException(this.kind, [this.detail]);

  @override
  String toString() => detail == null ? kind.name : '${kind.name}: $detail';
}

/// The names this project's releases carry, per platform.
///
/// The updater used to ask for FlClashX's assets (`FlClashX-android-arm64-v8a.apk` and
/// friends) in `pluralplay/FlClashX` — a repository this app does not ship from, and names no
/// release of its own publishes. A name nobody publishes is not a fallback: it is a download
/// that cannot exist, offered to the owner as an update. Android's name states the ABI, so the
/// arch list still decides which one is tried first; the desktop packages carry one name each.
const portalAndroidAssets = <String, String>{
  'arm64-v8a': 'Portal.apk',
  'armeabi-v7a': 'Portal_legacy.apk',
  'x86_64': 'Portal_x86-64.apk',
  'universal': 'Portal_universal.apk',
};

/// The same four builds under the names `build.sh apk` writes into `dist/` today.
///
/// The release is the contract and `portalAndroidAssets` is what it must publish; this list is
/// only so a build assembled by this repository's own script can be found by its own updater
/// before the release is renamed. It names this project's files and nothing else.
const portalAndroidDistNames = <String, String>{
  'arm64-v8a': 'Portal-android-arm64-v8a.apk',
  'armeabi-v7a': 'Portal-android-armeabi-v7a.apk',
  'x86_64': 'Portal-android-x86_64.apk',
  'universal': 'Portal-android-universal.apk',
};

/// `Portal-<version>-<arch>.deb` and its siblings: the version is inside the name, so the
/// release's own listing says which one it published.
bool matchesAssetGlob(String pattern, String name) {
  final star = pattern.indexOf('*');
  if (star < 0) return pattern == name;
  final prefix = pattern.substring(0, star);
  final suffix = pattern.substring(star + 1);
  return name.length > prefix.length + suffix.length &&
      name.startsWith(prefix) &&
      name.endsWith(suffix);
}

@immutable
class UpdateTarget {
  final UpdateInstallKind kind;

  /// Architectures in the order they are tried, as release assets name them.
  final List<String> archs;

  const UpdateTarget(this.kind, this.archs);

  /// This app's asset for [arch], when the name states the arch.
  String? assetName(String arch) => switch (kind) {
    UpdateInstallKind.android => portalAndroidAssets[arch],
    UpdateInstallKind.windows => 'Portal.exe',
    UpdateInstallKind.macos => 'Portal.dmg',
    // Linux packaging names carry a version, so they are matched, not built.
    UpdateInstallKind.appImage ||
    UpdateInstallKind.deb ||
    UpdateInstallKind.rpm => null,
    UpdateInstallKind.packageManager || UpdateInstallKind.unsupported => null,
  };

  /// The glob this target's release assets answer to, for the packages whose name carries a
  /// version. Null for every other kind.
  String? get assetGlob => switch (kind) {
    UpdateInstallKind.appImage => 'Portal-*.AppImage',
    UpdateInstallKind.deb => 'Portal-*.deb',
    UpdateInstallKind.rpm => 'Portal-*.rpm',
    _ => null,
  };

  bool get downloads =>
      archs.isNotEmpty && (assetName(archs.first) != null || assetGlob != null);

  /// Every name this target would accept, for the sentence a missing asset gets.
  String get expected {
    final names = <String>[];
    for (final arch in archs) {
      final name = assetName(arch);
      if (name != null && !names.contains(name)) names.add(name);
    }
    final glob = assetGlob;
    if (glob != null) names.add(glob);
    return names.isEmpty ? 'no ${kind.name} asset' : names.join(' | ');
  }

  /// The release asset this target takes, in the order [archs] are tried.
  ///
  /// Only a name from this list is a candidate: the release's own `assets` are searched, never
  /// another platform's file and never a name the release does not carry.
  String? pick(Iterable<String> names) {
    final listed = names.toSet();
    for (final arch in archs) {
      final exact = assetName(arch);
      if (exact != null) {
        if (listed.contains(exact)) return exact;
        final dist = kind == UpdateInstallKind.android
            ? portalAndroidDistNames[arch]
            : null;
        if (dist != null && listed.contains(dist)) return dist;
        continue;
      }
      final glob = assetGlob;
      if (glob == null) continue;
      final matches = [
        for (final name in names)
          if (matchesAssetGlob(glob, name)) name,
      ];
      if (matches.isEmpty) continue;
      // The version is in the name and so is the arch: a package built for another one is not
      // this device's update. A name that states no arch at all is the published one.
      final tokens = _archTokens[arch] ?? [arch];
      final preferred = matches
          .where((name) => tokens.any(name.contains))
          .firstOrNull;
      if (preferred != null) return preferred;
      final untagged = matches
          .where((name) => !_knownArchTokens.any(name.contains))
          .firstOrNull;
      if (untagged != null) return untagged;
    }
    return null;
  }
}

/// The way an arch appears inside a package name, most specific first.
const _archTokens = <String, List<String>>{
  'arm64': ['arm64', 'aarch64'],
  'aarch64': ['aarch64', 'arm64'],
  'amd64': ['amd64', 'x86_64', 'x64'],
  'x86_64': ['x86_64', 'amd64', 'x64'],
  'arm64-v8a': ['arm64', 'aarch64'],
  'armeabi-v7a': ['armeabi', 'armv7', 'arm'],
};

final _knownArchTokens = <String>{
  for (final tokens in _archTokens.values) ...tokens,
};

@immutable
class UpdateAsset {
  final String name;
  final Uri url;

  final Uri? checksumUrl;
  final String? checksum;
  final int? size;
  final Set<String> allowedHosts;

  const UpdateAsset({
    required this.name,
    required this.url,
    this.checksumUrl,
    this.checksum,
    this.size,
    this.allowedHosts = updateHosts,
  });

  int get sizeLimit => size ?? updateSizeCeiling;
}

bool isAllowedUpdateUri(Uri uri, {Set<String> hosts = updateHosts}) =>
    uri.scheme == 'https' &&
    hosts.contains(uri.host.toLowerCase()) &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443);

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

/// A provider manifest's binary may sit on any HTTPS host: its inline hash,
/// from the signed manifest, vouches for it. The update hosts stay allowed
/// because a GitHub release download redirects to its asset CDN.
UpdateAsset manifestUpdateAsset(
  Map<String, dynamic> manifest,
  UpdateTarget target,
) {
  final listed = manifest['assets'];
  final assets = <String, Map>{
    if (listed is List)
      for (final asset in listed)
        if (asset is Map && asset['name'] is String)
          asset['name'] as String: asset,
  };
  final name = target.pick(assets.keys);
  if (name == null) {
    throw UpdateException(UpdateErrorKind.noAsset, target.expected);
  }
  final asset = assets[name]!;
  final rawUrl = asset['url'];
  final uri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    throw UpdateException(UpdateErrorKind.untrustedHost, '$rawUrl');
  }
  final sha = asset['sha256'];
  if (sha is! String || !_sha256Pattern.hasMatch(sha)) {
    throw UpdateException(UpdateErrorKind.noChecksum, name);
  }
  return UpdateAsset(
    name: name,
    url: uri,
    checksum: sha.toLowerCase(),
    allowedHosts: {...updateHosts, uri.host.toLowerCase()},
  );
}

/// Android ABIs as `Build.SUPPORTED_ABIS` lists them, mapped onto the split
/// APKs a release carries, with the universal one last.
List<String> androidUpdateArchs(List<String> supportedAbis) => [
  for (final abi in supportedAbis)
    if (const {'arm64-v8a', 'armeabi-v7a', 'x86_64'}.contains(abi)) abi,
  'universal',
];

final _tagPattern = RegExp(r'^v\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$');

/// The tag decides the channel when the release itself does not say: only a
/// pre-release tag carries a suffix.
bool releaseMatchesChannel(Map<String, dynamic> release, {required bool pre}) {
  final tag = release['tag_name'];
  if (tag is! String || !_tagPattern.hasMatch(tag)) {
    return false;
  }
  final flagged = release['prerelease'];
  final isPre = flagged is bool ? flagged : tag.contains('-');
  return isPre == pre && tag.contains('-') == pre;
}

Uri releasePageOf(Map<String, dynamic> release, {required String repository}) {
  final page = Uri.tryParse('${release['html_url']}');
  if (page != null && isAllowedUpdateUri(page) && page.host == 'github.com') {
    return page;
  }
  final tag = release['tag_name'];
  return Uri.parse(
    tag is String && _tagPattern.hasMatch(tag)
        ? 'https://github.com/$repository/releases/tag/$tag'
        : 'https://github.com/$repository/releases',
  );
}

UpdateAsset selectUpdateAsset(
  Map<String, dynamic> release,
  UpdateTarget target, {
  required String repository,
  required bool pre,
}) {
  if (!releaseMatchesChannel(release, pre: pre)) {
    throw const UpdateException(UpdateErrorKind.noAsset, 'channel');
  }
  final tag = release['tag_name'] as String;
  final listed = release['assets'];
  if (listed is! List) {
    return _assetFromTag(target, repository: repository, tag: tag);
  }
  final assets = <String, Map>{
    for (final asset in listed)
      if (asset is Map && asset['name'] is String)
        asset['name'] as String: asset,
  };
  final name = target.pick(assets.keys);
  if (name == null) {
    throw UpdateException(UpdateErrorKind.noAsset, target.expected);
  }
  final asset = assets[name]!;
  final checksum = assets['$name.sha256'];
  if (checksum == null) {
    throw UpdateException(UpdateErrorKind.noChecksum, name);
  }
  final size = asset['size'];
  if (size is int && size > updateSizeCeiling) {
    throw UpdateException(UpdateErrorKind.tooLarge, name);
  }
  return UpdateAsset(
    name: name,
    url: _assetUri(asset, name),
    checksumUrl: _assetUri(checksum, '$name.sha256'),
    size: size is int && size > 0 ? size : null,
  );
}

UpdateAsset _assetFromTag(
  UpdateTarget target, {
  required String repository,
  required String tag,
}) {
  final name = target.assetName(target.archs.firstOrNull ?? '');
  if (name == null) {
    // A name this build cannot write down is a name it must not guess: the answer is that the
    // release carries nothing for this platform, not a URL nobody published.
    throw UpdateException(UpdateErrorKind.noAsset, target.expected);
  }
  final base = 'https://github.com/$repository/releases/download/$tag';
  return UpdateAsset(
    name: name,
    url: Uri.parse('$base/$name'),
    checksumUrl: Uri.parse('$base/$name.sha256'),
  );
}

Uri _assetUri(Map asset, String name) {
  final raw = asset['browser_download_url'];
  final uri = raw is String ? Uri.tryParse(raw) : null;
  if (uri == null ||
      !isAllowedUpdateUri(uri) ||
      uri.pathSegments.lastOrNull != name) {
    throw UpdateException(UpdateErrorKind.untrustedHost, '$raw');
  }
  return uri;
}

final _gnuLine = RegExp(r'^([0-9a-fA-F]{64})(?:\s+\*?(.+))?$');
final _bsdLine = RegExp(r'^SHA256 \((.+)\) = ([0-9a-fA-F]{64})$');

/// Reads `sha256sum` and BSD `shasum` output. A line naming another file is
/// skipped; a lone hash counts only when nothing names [assetName].
String? parseChecksum(String text, String assetName) {
  String? bare;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.replaceFirst('﻿', '').trim();
    final String hash;
    final String? name;
    if (_gnuLine.firstMatch(line) case final match?) {
      hash = match.group(1)!;
      name = match.group(2)?.trim();
    } else if (_bsdLine.firstMatch(line) case final match?) {
      hash = match.group(2)!;
      name = match.group(1);
    } else {
      continue;
    }
    if (name == null) {
      bare ??= hash.toLowerCase();
    } else if (p.posix.basename(name.replaceAll(r'\', '/')) == assetName) {
      return hash.toLowerCase();
    }
  }
  return bare;
}
