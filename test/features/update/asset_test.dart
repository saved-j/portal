import 'package:fl_clash/features/update/asset.dart';
import 'package:flutter_test/flutter_test.dart';

const _repository = 'saved-j/portal';

Map<String, dynamic> _asset(String name, {int size = 1000, String? url}) => {
  'name': name,
  'size': size,
  'browser_download_url':
      url ?? 'https://github.com/$_repository/releases/download/v0.5.1/$name',
};

Map<String, dynamic> _release(
  List<String> names, {
  String tag = 'v0.5.1',
  bool? prerelease,
}) => {
  'tag_name': tag,
  'prerelease': ?prerelease,
  'assets': [
    for (final name in names) ...[_asset(name), _asset('$name.sha256')],
  ],
};

Matcher _fails(UpdateErrorKind kind) =>
    throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', kind));

void main() {
  group('selectUpdateAsset', () {
    const allAssets = [
      'Portal.apk',
      'Portal_legacy.apk',
      'Portal_universal.apk',
      'Portal.exe',
      'Portal.dmg',
      'Portal-1.0.3-linux-amd64.AppImage',
      'Portal-1.0.3-linux-amd64.deb',
      'Portal-1.0.3-linux-amd64.rpm',
      'Portal-1.0.3-linux-arm64.deb',
    ];

    String select(UpdateTarget target, {List<String> names = allAssets}) =>
        selectUpdateAsset(
          _release(names, prerelease: false),
          target,
          repository: _repository,
          pre: false,
        ).name;

    test('takes the first supported ABI a release builds', () {
      final archs = androidUpdateArchs(['x86', 'arm64-v8a', 'armeabi-v7a']);
      expect(archs, ['arm64-v8a', 'armeabi-v7a', 'universal']);
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.android, ['x86_64'])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        select(UpdateTarget(UpdateInstallKind.android, archs)),
        'Portal.apk',
      );
    });

    test('the asset this app publishes, and the name says the arch', () {
      expect(portalAndroidAssets['arm64-v8a'], 'Portal.apk');
      expect(portalAndroidAssets['armeabi-v7a'], 'Portal_legacy.apk');
      expect(portalAndroidAssets['x86_64'], 'Portal_x86-64.apk');
      expect(portalAndroidAssets['universal'], 'Portal_universal.apk');
      expect(
        const UpdateTarget(UpdateInstallKind.windows, ['amd64']).assetName(
          'amd64',
        ),
        'Portal.exe',
      );
      expect(
        const UpdateTarget(UpdateInstallKind.macos, ['arm64']).assetName(
          'arm64',
        ),
        'Portal.dmg',
      );
      expect(
        const UpdateTarget(UpdateInstallKind.deb, ['amd64']).assetGlob,
        'Portal-*.deb',
      );
    });

    test("another project's asset is never offered", () {
      // The repository this app used to point at published FlClashX's names. A file for the
      // same platform is not this app's build: it must be neither chosen nor offered.
      expect(
        () => select(
          const UpdateTarget(UpdateInstallKind.android, ['arm64-v8a']),
          names: const [
            'FlClashX-android-' 'arm64-v8a.apk',
            'FlClashX-android-' 'universal.apk',
          ],
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('a missing asset says which name it looked for', () {
      expect(
        () => select(
          const UpdateTarget(UpdateInstallKind.android, ['arm64-v8a', 'universal']),
          names: const ['Portal.exe'],
        ),
        throwsA(
          isA<UpdateException>()
              .having((e) => e.kind, 'kind', UpdateErrorKind.noAsset)
              .having((e) => e.detail, 'detail', 'Portal.apk | Portal_universal.apk'),
        ),
      );
    });

    test('also finds the names dist/ writes today', () {
      expect(
        select(
          const UpdateTarget(UpdateInstallKind.android, ['arm64-v8a', 'universal']),
          names: const ['Portal-android-arm64-v8a.apk'],
        ),
        'Portal-android-arm64-v8a.apk',
      );
      expect(
        select(
          const UpdateTarget(UpdateInstallKind.android, ['arm64-v8a']),
          names: const ['Portal-android-arm64-v8a.apk', 'Portal.apk'],
        ),
        'Portal.apk',
      );
    });

    test('falls back to the universal APK', () {
      expect(
        select(
          UpdateTarget(UpdateInstallKind.android, androidUpdateArchs(['x86'])),
        ),
        'Portal_universal.apk',
      );
    });

    test('picks the desktop package for the install type and arch', () {
      expect(
        select(const UpdateTarget(UpdateInstallKind.windows, ['arm64'])),
        'Portal.exe',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.macos, ['amd64'])),
        'Portal.dmg',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.appImage, ['amd64'])),
        'Portal-1.0.3-linux-amd64.AppImage',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.deb, ['arm64'])),
        'Portal-1.0.3-linux-arm64.deb',
      );
      expect(
        select(const UpdateTarget(UpdateInstallKind.rpm, ['amd64'])),
        'Portal-1.0.3-linux-amd64.rpm',
      );
    });

    test('never substitutes another arch or package type', () {
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.rpm, ['arm64'])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        () => select(const UpdateTarget(UpdateInstallKind.appImage, [])),
        _fails(UpdateErrorKind.noAsset),
      );
      expect(
        () => select(
          const UpdateTarget(UpdateInstallKind.packageManager, ['amd64']),
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('holds a release to the channel the app runs on', () {
      final pre = _release(
        ['Portal.dmg'],
        tag: 'v0.5.2-pre.1',
        prerelease: true,
      );
      const target = UpdateTarget(UpdateInstallKind.macos, ['arm64']);
      expect(
        selectUpdateAsset(pre, target, repository: _repository, pre: true).name,
        'Portal.dmg',
      );
      expect(
        () =>
            selectUpdateAsset(pre, target, repository: _repository, pre: false),
        _fails(UpdateErrorKind.noAsset),
      );
      final stable = _release(['Portal.dmg'], prerelease: false);
      expect(
        () => selectUpdateAsset(
          stable,
          target,
          repository: _repository,
          pre: true,
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('rejects a tag that is not a version', () {
      final release = _release(['Portal.dmg'], tag: 'v1/../x');
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('requires a published checksum', () {
      final release = {
        'tag_name': 'v0.5.1',
        'assets': [_asset('Portal.dmg')],
      };
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.noChecksum),
      );
    });

    test('caps the size at the release figure and the ceiling', () {
      final asset = selectUpdateAsset(
        _release(['Portal.dmg']),
        const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
        repository: _repository,
        pre: false,
      );
      expect(asset.size, 1000);
      expect(asset.sizeLimit, 1000);
      final huge = {
        'tag_name': 'v0.5.1',
        'assets': [
          _asset('Portal.dmg', size: updateSizeCeiling + 1),
          _asset('Portal.dmg.sha256'),
        ],
      };
      expect(
        () => selectUpdateAsset(
          huge,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.tooLarge),
      );
    });

    test('refuses an asset URL off the allowlist', () {
      final release = {
        'tag_name': 'v0.5.1',
        'assets': [
          _asset(
            'Portal.dmg',
            url: 'https://evil.example/Portal.dmg',
          ),
          _asset('Portal.dmg.sha256'),
        ],
      };
      expect(
        () => selectUpdateAsset(
          release,
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          repository: _repository,
          pre: false,
        ),
        _fails(UpdateErrorKind.untrustedHost),
      );
    });

    test('builds the URL from the tag when the lookup had no assets', () {
      final asset = selectUpdateAsset(
        {'tag_name': 'v0.5.1'},
        const UpdateTarget(UpdateInstallKind.windows, ['amd64']),
        repository: _repository,
        pre: false,
      );
      expect(
        asset.url.toString(),
        'https://github.com/$_repository/releases/download/v0.5.1/'
        'Portal.exe',
      );
      expect(asset.checksumUrl!.path, endsWith('Portal.exe.sha256'));
      expect(asset.size, isNull);
      expect(asset.sizeLimit, updateSizeCeiling);
    });
  });

  test('only a known package and arch offer a download', () {
    expect(
      const UpdateTarget(UpdateInstallKind.macos, ['arm64']).downloads,
      isTrue,
    );
    expect(const UpdateTarget(UpdateInstallKind.macos, []).downloads, isFalse);
    expect(
      const UpdateTarget(UpdateInstallKind.packageManager, ['amd64']).downloads,
      isFalse,
    );
    expect(
      const UpdateTarget(UpdateInstallKind.unsupported, ['amd64']).downloads,
      isFalse,
    );
  });

  test('allowlist takes only HTTPS on the GitHub download hosts', () {
    expect(isAllowedUpdateUri(Uri.parse('https://github.com/a')), isTrue);
    expect(
      isAllowedUpdateUri(
        Uri.parse('https://release-assets.githubusercontent.com/x'),
      ),
      isTrue,
    );
    expect(
      isAllowedUpdateUri(Uri.parse('https://objects.githubusercontent.com/x')),
      isTrue,
    );
    expect(isAllowedUpdateUri(Uri.parse('http://github.com/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://github.com:8443/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://u@github.com/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://github.com.evil/a')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('https://gist.github.com/a')), isFalse);
  });

  group('parseChecksum', () {
    const hash =
        '3dad780109d1524106a07cc6499c7f0fb04f08290b0eb931a5f7bbcf2c153058';
    const name = 'Portal.dmg';

    test('reads the sha256sum line a release publishes', () {
      expect(parseChecksum('$hash  ./$name\n', name), hash);
      expect(parseChecksum('$hash *$name\r\n', name), hash);
      expect(parseChecksum('﻿${hash.toUpperCase()}  $name', name), hash);
    });

    test('reads BSD shasum output and a bare hash', () {
      expect(parseChecksum('SHA256 ($name) = $hash', name), hash);
      expect(parseChecksum('$hash\n', name), hash);
    });

    test('ignores lines for other files and malformed lines', () {
      final other = 'f' * 64;
      expect(parseChecksum('$other  other.dmg\n$hash  $name', name), hash);
      expect(parseChecksum('$other  other.dmg', name), isNull);
      expect(parseChecksum('not a hash  $name', name), isNull);
      expect(parseChecksum('${hash.substring(1)}  $name', name), isNull);
      expect(parseChecksum('', name), isNull);
    });
  });

  group('manifestUpdateAsset', () {
    final sha = 'a' * 64;
    Map<String, dynamic> manifest(String name, {String? url, Object? sha256}) =>
        {
          'version': 'v0.5.2',
          'assets': [
            {
              'name': name,
              'url': url ?? 'https://mirror.example/v0.5.2/$name',
              'sha256': sha256 ?? sha,
            },
          ],
        };

    test('picks the asset for the platform with its inline hash', () {
      final asset = manifestUpdateAsset(
        manifest('Portal.exe'),
        const UpdateTarget(UpdateInstallKind.windows, ['amd64']),
      );
      expect(asset.url.host, 'mirror.example');
      expect(asset.checksum, sha);
      expect(asset.checksumUrl, isNull);
      expect(asset.allowedHosts, {...updateHosts, 'mirror.example'});
    });

    test('a missing asset for the platform fails', () {
      expect(
        () => manifestUpdateAsset(
          manifest('Portal.exe'),
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
        ),
        _fails(UpdateErrorKind.noAsset),
      );
    });

    test('a non-https binary url is refused', () {
      expect(
        () => manifestUpdateAsset(
          manifest(
            'Portal.dmg',
            url: 'http://mirror.example/x.dmg',
          ),
          const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
        ),
        _fails(UpdateErrorKind.untrustedHost),
      );
    });

    test('a malformed or missing hash is refused', () {
      for (final bad in ['xyz', 'a' * 63]) {
        expect(
          () => manifestUpdateAsset(
            manifest('Portal.dmg', sha256: bad),
            const UpdateTarget(UpdateInstallKind.macos, ['arm64']),
          ),
          _fails(UpdateErrorKind.noChecksum),
        );
      }
      expect(
        () => manifestUpdateAsset(const {
          'version': 'v0.5.2',
          'assets': [
            {
              'name': 'Portal.dmg',
              'url': 'https://mirror.example/x.dmg',
            },
          ],
        }, const UpdateTarget(UpdateInstallKind.macos, ['arm64'])),
        _fails(UpdateErrorKind.noChecksum),
      );
    });
  });

  test('release page stays on github.com', () {
    expect(
      releasePageOf({
        'tag_name': 'v0.5.1',
        'html_url': 'https://github.com/$_repository/releases/tag/v0.5.1',
      }, repository: _repository).toString(),
      'https://github.com/$_repository/releases/tag/v0.5.1',
    );
    expect(
      releasePageOf({
        'tag_name': 'v0.5.2-pre.1',
        'html_url': 'https://evil.example/',
      }, repository: _repository).toString(),
      'https://github.com/$_repository/releases/tag/v0.5.2-pre.1',
    );
  });
}
