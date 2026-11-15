# Building Portal from a clean clone

The goal: `git clone`, run one command, get the same application that is installed on the
author's machines. Several build steps are pinned, and a floating version changes the
output, so the exact toolchain is listed first.

## Pinned toolchain

| tool | version | pinned in |
|---|---|---|
| Flutter | **3.47.9** (stable, framework revision `c197ca5199`) | `.github/workflows/build.yaml` (`FLUTTER_VERSION`) |
| Dart | bundled with Flutter 3.47.9 | `pubspec.lock` is committed |
| JDK | **17** | `android/app/build.gradle.kts` (`VERSION_17`), CI uses Temurin 17 |
| Gradle | **9.8.0** | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle plugin | **9.4.1** | `android/settings.gradle.kts` |
| Kotlin | **2.4.20** | `android/settings.gradle.kts` |
| Android SDK | **compileSdk 37 / targetSdk 37 / minSdk 24** | `android/gradle/libs.versions.toml` |
| Android NDK | **28.2.13676358** (r28c) | `android/gradle/libs.versions.toml` |
| Go | **1.27.0** | `core/go.mod`; CI builds with 1.27.1 |
| Rust | **1.99.0** | `plugins/rust_api/rust/rust-toolchain.toml` |
| Xcode | **26.3** (26.2 also works) | CI picks `Xcode_26.3` |

`services/helper` has no toolchain file of its own and builds with the same stable Rust as
`plugins/rust_api`. `minSdk` is read from the version catalog by every Android module,
including `plugins/wifi_ssid`, so raising it is a one-line change in one file.

China mirrors (`FLUTTER_STORAGE_BASE_URL`, `RUSTUP_DIST_SERVER`, USTC crates) are optional:
they change download speed, not the output.

## Environment

```bash
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/android-sdk     # platform 37, build-tools, NDK 28.2.13676358
export PATH="/path/to/flutter/bin:$HOME/.cargo/bin:/path/to/go/bin:$PATH"

./build.sh get     # flutter pub get
```

`build.sh` falls back to the author's macOS paths only when these variables are unset; on any
other machine set them explicitly. The Go core, the Rust helper and the Rust plugin library
compile through the pub build hook — there is nothing to build by hand and no submodule.

## Android APK

```bash
./build.sh apk
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# -> dist/Portal-android-arm64-v8a.apk, -armeabi-v7a, -x86_64, -universal
```

One ABI only: `dart setup.dart android --env stable --arch arm64`.

The core is not a stored binary and not a child process: it is a c-shared library loaded
into the app with `System.loadLibrary("xray")` and given the tun descriptor in-process, at
`android/app/src/main/jniLibs/arm64-v8a/libxray.so`. `build/xray-lib.sh` builds it — that
script owns the Go and NDK invocation, and this document does not repeat it. It is not built
by `build.sh`, so a machine that only packages a release needs no Go toolchain; it does need
the library to be there, and `build.sh apk` refuses to start without it.

The library must export the three JNI entry points the plugin declares —
`Java_com_follow_clashx_plugins_XrayPlugin_XrayStart`, `…_XrayStop`, `…_XrayVersion` —
wrapping the plain C API `XrayStart(configJSON, tunFd)`, `XrayStop()`, `XrayVersion()`. A
library built without them still loads, and then fails the first start with "missing its JNI
entry points" — a packaging fault, not a core refusing a config, and worth catching by hand
before an APK carries it.

A digest is optional: set `XRAY_LIB_SHA256` in the environment (or in `build.sh`) to pin one
and a different file fails the packaging step; leave it unset and whatever
`build/xray-lib.sh` produced is what ships, which is the normal case for a working tree. The
digest is read with `sha256sum`, or `shasum -a 256` where coreutils is not installed.

The geodata the panel's rules name (`geosite:`/`geoip:`) stays where it was: `assets/xray/`
is a Flutter asset directory, and the plugin copies the two `.dat` files into `filesDir` on
first start and points `XRAY_LOCATION_ASSET` at them.

`jniLibs` is packaged with `useLegacyPackaging = true`: the library is stored uncompressed in
the APK and extracted to `nativeLibraryDir` at install, which is what `System.loadLibrary`
reads and the only directory an app targeting API 29+ may map an executable from. Flutter's
ABI lookup expects the same layout, so the four-ABI split builds keep working.

Gradle needs no network beyond the pinned wrapper: `android/gradlew`, `gradlew.bat` and
`gradle-wrapper.jar` are committed, and the wrapper verifies the distribution against the
checksum in `gradle-wrapper.properties`.

```bash
cd android && ./gradlew :app:assembleRelease   # the wrapper path, from a fresh clone
```

## Linux: deb, rpm, AppImage

Linux bundles are built on Linux only — Flutter has no cross-compile for desktop, and
`build.sh` refuses the other way around. Build dependencies:

```bash
sudo apt-get install -y ninja-build libgtk-3-dev libayatana-appindicator3-dev libsecret-1-dev
# plus the packaging tools of the formats you ask for: dpkg-deb, rpmbuild, appimagetool
```

They are not installed by the build. A missing one is reported by name with the command that
installs it, and the build stops there; `PORTAL_INSTALL_DEPS=1` opts in to the script running
those commands (sudo apt-get, and a download of `appimagetool` into `/usr/local/bin`).

```bash
dart setup.dart linux --env stable                      # all three
dart setup.dart linux --env stable --targets deb        # dist/Portal-linux-amd64.deb
dart setup.dart linux --env stable --targets rpm        # dist/Portal-linux-amd64.rpm
dart setup.dart linux --env stable --targets appimage   # dist/Portal-linux-amd64.AppImage
```

The rpm `Version` field cannot contain a hyphen, so a version such as `0.5.3-portal-duo`
becomes `Version: 0.5.3` with `Release: portal-duo.1`. The deb and rpm postuninstall hooks
remove `/etc/systemd/system/flclashx-helper.service`, the unit the app writes on demand; the
unit name is fixed by the package identity and is not a display name.

## Windows

Builds on Windows only (`build.sh windows` guards the host):

```bash
dart setup.dart windows --env stable
# -> dist/Portal-windows-amd64.zip and dist/Portal-windows-amd64-setup.exe (Inno Setup 6)
```

## macOS

Builds on macOS only:

```bash
APPLE_DEVELOPER_ID="Developer ID Application: Name (TEAMID)" ./build.sh macos
# -> dist/Portal-macos-arm64.dmg, signed
```

The image is signed with `APPLE_DEVELOPER_ID`. Without it the build refuses to cut a
distributable DMG: an unsigned one is blocked by Gatekeeper on any other machine, and handing
someone a file they have to be told how to bypass is not a build. A local build says so
explicitly and gets an unsigned image that is meant for this machine only:

```bash
PORTAL_ALLOW_UNSIGNED=1 ./build.sh macos
```

`create-dmg` is a build dependency and is not installed automatically either: the script names
it and the command that installs it, and `PORTAL_INSTALL_DEPS=1` lets the build run that
command. Notarization is not part of any build here.

## What the repository does not contain

- **The signing keystore.** `android/app/build.gradle.kts` reads `storePassword`, `keyAlias`
  and `keyPassword` from `android/local.properties` and signs with `android/app/keystore.jks`.
  Neither the keystore nor the passwords are published: a keystore is the app's identity.
  Without them Gradle falls back to the debug key and adds the `.dev` application id suffix,
  so the APK installs side by side with a release build instead of replacing it. Same code,
  same resources, different signature.
- **The core library.** Built with `build/xray-lib.sh` as described above; `build.sh` checks
  only that it is present, and verifies its digest when one is pinned.
- **The Gradle and pub caches.** Anything in `~/.work` on the author's machine is a cache,
  not input.

## Reading a device's own record

The portal writes three files into the app's **external** files directory, which `adb shell`
can read on a release build (`filesDir` cannot: `run-as` refuses a package that is not
debuggable). The names are constants in
`android/common/src/main/java/com/follow/clashx/common/PortalTelemetry.kt`:

```bash
DIR=/sdcard/Android/data/io.portal.xfc.dev/files     # the .dev suffix is the unsigned flavour
adb shell tail -5 $DIR/portal-status.log             # heartbeat, one line every ~5 s
adb shell tail -20 $DIR/portal-transitions.log       # one line per open/close/switch/revoke
adb shell tail -40 $DIR/xray.log                     # the core's own log (the tun document's)
adb pull $DIR/portal-status.log
```

The heartbeat line is fixed in shape and answers the one question logcat could not:

```
time=... owner=<Mihomo|Xray|Off> generation=<n> fdEpoch=<n> phase=<Off|Starting|Active|Stopping|Failed> engine=<running|stopped> child=<running|stopped> listeners=<ip:port,...|none|unknown> egress=<ip|unknown>
```

`listeners` is read from the app's own rows of `/proc/self/net/tcp{,6}`. That read is denied
to an `untrusted_app` on Android 10+, so the fallback is a measured one: a loopback TCP
handshake against the mixed port and the cores' defaults, reported as `probed:127.0.0.1:…`
only for the ports that answered, and `unknown` when none did. In the simple portal there
must be one reader and one loopback port, never a second core's. `egress` is this app's own
probe, so in the simple portal it leaves outside the tunnel by design (the service keeps this
uid out of it); a device-side `curl` is what proves the node's address, e.g.

```bash
adb shell 'curl -sS -m 15 -o /dev/null -w "%{http_code}\n" https://www.google.com'
adb shell 'curl -sS -m 10 https://api.ipify.org'
```

A debug build keeps the same record and the same logcat mirror.

`portal-transitions.log` carries one plain line per transition (`time= from= to= generation=
phase= why= result=`), and after a tap on the mode switch, two measured ones:

```
time=... kind=switch phase=active duration_ms=236 from=Xray to=Mihomo generation=7
time=... kind=switch phase=list duration_ms=41 from=Xray to=Mihomo mode=rule owner=engine source=live rows=28 names=VPN - Main | 🇫🇮 Финляндия 01 | …
```

`phase=active` is written by the record's own `onPublish` hook — the tap starts the clock on
the native side and `Active` is published only after the owner acknowledged its listener or
tunnel, so the number is the hand-over, not a wait for a config. `phase=list` is the screen's
clock, from the tap to the first frame with rows, `mode=` is the mode those rows were drawn in,
`owner=` is the core they belong to, `names=` is the first three rows it actually showed, and
`source=` says whose rows they were: the current owner's (`live`), the last group this owner's
list drew (`held`, which is what keeps the screen from going empty), the engine's own last answer
for this profile (`cache`), the profile's own `proxies:` (`profile`) or the simple portal's
servers (`servers`). A switch that fails writes neither: it is reported as a failure, with the
plain transition lines of its rollback.

A row source is the owner's, and only the owner's. `live` counts only when the core that holds
the tunnel is the mode's own — the engine's groups stay in memory after the engine stops, and a
list that drew them under the simple portal (or the child's servers under the network mode) was
showing the previous owner's servers, each name real and the list wrong. `held` is kept per
owner for the same reason, and the transition line carries `owner=` and `names=` so this cannot
happen silently again.

Each mode has one source of rows and no other: the simple portal's list is the Xray document
(`xrayServersProvider`, read from the profile's second format), the network mode's is the
engine's groups — or, with the portal closed, the engine's own last answer for this profile and
then the profile's engine-format `proxies:`. Neither mode can draw the other's names, and a
group held from the other mode is dropped when the mode changes.

A delay is measured by the core that holds the server, and by nothing else. The engine's rows
carry the engine's own delay, taken through the tunnel it built. The simple portal's rows carry
a TCP handshake timed by this process against the node's resolved address — and a node name
that resolves only into the tunnel's own range (`198.18.0.0/15`, the fake-IP range, including
the tun's gateway `198.18.0.1` and resolver `198.18.0.2`) is drawn as `—` and logged as such,
because a handshake there completes against the core's local listener and reports the phone's
own loop as a delay:

```
portal delay Эстония: ee.example:8443 → 198.18.0.5 is the tunnel's own address, no number
portal delay Финляндия: fi.example:443 → 185.155.222.6 214 ms
```

`adb logcat -s flutter` carries those lines; the dash on the row and the line are the same fact.

## Updates

The updater reads `saved-j/portal` (`repository` in `lib/common/constant.dart`) and looks only
for the names this project publishes:

| platform | install kind | asset |
|---|---|---|
| Android arm64 | `UpdateInstallKind.android` | `Portal.apk` |
| Android arm32 | same, `armeabi-v7a` | `Portal_legacy.apk` |
| Android x86_64 | same, `x86_64` | `Portal_x86-64.apk` |
| Android, any ABI's fallback | same, `universal` | `Portal_universal.apk` |
| Windows | `windows` | `Portal.exe` |
| macOS | `macos` | `Portal.dmg` |
| Linux | `appImage` / `deb` / `rpm` | `Portal-*.AppImage` / `Portal-*.deb` / `Portal-*.rpm` |

`./build.sh apk` writes `dist/Portal-android-<abi>.apk` today; the updater accepts those four
names too (`portalAndroidDistNames`), after the published ones. Nothing from another project is
accepted under any name.

The Linux names carry a version, so the release's own `assets` list decides which one it
published; an arch token in the name (`linux-arm64`, `linux-amd64`) still has to be this
device's. A release that carries nothing for this platform/arch is reported as
`updateErrorNoAsset` with the names it looked for, e.g. `This release has no build for this
device.` over `Portal.apk | Portal_universal.apk` — never another project's file. The download
line names both facts:

```
[APP] update: repository=saved-j/portal asset=Portal.apk url=https://github.com/saved-j/portal/releases/download/v1.0.3/Portal.apk
```

## Checks

```bash
bash -n build.sh
flutter analyze lib/
dart run tool/test.dart
```

## The patch pipeline

`pipeline/1.01a` is a single frozen series against upstream FlClashX (`5b4d0669`);
`./apply.sh 1.01a verify` clones the upstream base, applies the series and proves by tree hash
that the result equals the product tree the series declares. `pipeline/1.02a` continues the
same way, one topic per patch, each patch applying to the frozen tree on its own.
