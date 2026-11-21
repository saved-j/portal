# 1.02a patches 07–14: build, packaging, docs

Each patch is a single unified diff against `873e0ede` (the 1.01a freeze). Every one applies
to that tree on its own, and the eight apply in order with `git apply`.

| patch | files | what it settles |
|---|---|---|
| 07-manifest-backup-export | `android/app/src/main/AndroidManifest.xml` | no backup, `QuickActionActivity` closed, one-line reasons on the three exports that must stay |
| 08-xray-digest | `build.sh` | `XRAY_VERSION` + `XRAY_SHA256` pinned together, digest mismatch aborts the APK build and names the expected hash |
| 09-gradle-wrapper | `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/.gitignore` | the wrapper is source; properties pin the distribution and its SHA-256 |
| 10-build-doc | `BUILD.md` | pinned toolchain and the commands for APK, deb, rpm, AppImage, Windows, macOS |
| 11-minsdk-catalog | `android/app/build.gradle.kts`, `plugins/wifi_ssid/android/build.gradle` | one SDK floor, read from `libs.versions.toml` |
| 12-rpm-version-and-packaging-names | `setup.dart`, `linux/packaging/deb/make_config.yaml`, `linux/packaging/rpm/make_config.yaml`, `windows/packaging/exe/make_config.yaml`, `test/setup_test.dart` | rpm `Version`/`Release` split, deb/rpm/Windows display and generic names, Windows exe name that actually exists |
| 13-appimage-branding | `linux/packaging/appimage/make_config.yaml` | AppImage `display_name`/`generic_name` |
| 14-readme-trilingual | `README.md`, removes `README_EN.md` and `README_ZH.md` | one README, Русский / English / 中文 |

## Decisions worth knowing

- **Package identity stays `flclashx`.** Names are display strings only: `display_name`,
  `generic_name`, `app_name`, `executable_name`. `Package: flclashx`, the artifact prefix
  `Portal-…`, `/opt/Portal` and `/usr/share/applications/io.portal.xfc.desktop` do not move.
- **The Helper unit stays `flclashx-helper.service`.** The name comes from
  `DesktopIdentity.helperUnit` and from `lib/common/desktop_channel.dart`, which is where the
  app writes the unit; the packaging hooks are substituted from the same value
  (`channelScripts`). Renaming it here alone would leave deb/rpm removing a unit the app never
  wrote, and `test/tool/packaging_config_test.dart` pins the string.
- **AppImage is patch 13, not 12.** 12 covers deb, rpm and Windows; 13 owns the whole AppImage
  file so no file is split across two patches.
- **`keywords: FlClashX` stays** in all three Linux configs: it is how people who knew the app
  by its old name find it, and it is a search alias, not a display string.
- **The wrapper is generated, not copied.** `android/gradlew`, `gradlew.bat` and
  `gradle-wrapper.jar` come from `gradle wrapper` of the 9.8.0 distribution itself
  (`--distribution-type all`), and `distributionSha256Sum` is
  `46ac66d47f30f3dacfdf306e0b714a91a34fb94a22ba0a744b280933f47bc0cf`, checked against the
  downloaded archive and against `services.gradle.org`. A wrapper jar copied from elsewhere
  would not match the distribution it unpacks.
- **`plugins/wifi_ssid` reads the catalog** by walking up from `rootProject.projectDir`, which
  resolves both when the plugin is a subproject of `android/` and when it is built on its own;
  a standalone build with no catalog at all keeps 24 as its floor.
- **Not touched, on purpose:** the deb/rpm `maintainer`/`packager` fields (they still say
  `pluralplay`, the upstream author — an identity change nobody has decided yet),
  `pubspec.yaml`'s description, `release.sh`'s example artifact names, `macos/packaging/dmg/
  make_config.yaml` (dead file: `setup.dart` calls `create-dmg` directly), and
  `windows/packaging/exe/inno_setup.iss`'s `Pos('FlClashX', …)` check, which is what lets the
  new installer adopt an old FlClashX registration.

## Verification

```
fresh worktree at 873e0ede, patches 07…14 applied in order: applied, no conflicts
git add -A && git write-tree        44691c15df549d1155c48c4e4a36b22a5c072da4
bash -n build.sh                    ok
cd android && ./gradlew --version   Gradle 9.8.0, checksum verified by the wrapper
flutter analyze lib/                12 issues, the same 12 as 873e0ede (0 introduced)
flutter test test/setup_test.dart test/tool/packaging_config_test.dart   34 passed
```

The 12 analyzer findings are `prefer_const_constructors`, two `deprecated_member_use` and nine
`undefined_hidden_name` warnings from the pinned `material_ui 1.5.0`; all live in `lib/`, which
none of these patches touches.
