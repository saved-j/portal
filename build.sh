#!/bin/bash
# Portal build driver. One place for the environment; nothing lands in $HOME.
#
#   ./build.sh get        flutter pub get
#   ./build.sh macos      macOS .app (host: macOS + Xcode)
#   ./build.sh apk        Android .apk (host: any OS with SDK+NDK)
#   ./build.sh linux      Linux bundle (host: Linux only)
#   ./build.sh windows    Windows bundle (host: Windows only)
#   ./build.sh ios        iOS — not available, see below
#   ./build.sh run-macos  open the built .app
#
# Toolchain used on Mark's Mac: Flutter in /opt/homebrew/opt/flutter, JDK 17 keg-only,
# Xcode via DEVELOPER_DIR, Rust toolchain 1.99.0 pinned by plugins/rust_api/rust/rust-toolchain.toml.
# Mirrors are the builder's network choice, not the product's: PORTAL_CHINA_MIRRORS=1 turns
# on the set used from China (flutter engine artifacts, rustup). Nothing is redirected by
# default, and anything already exported wins.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.work/.android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.work/.gradle}"
export PUB_CACHE="${PUB_CACHE:-$HOME/.work/.pub-cache}"
if [ "${PORTAL_CHINA_MIRRORS:-0}" = "1" ]; then
  # Do NOT point PUB_HOSTED_URL at pub.flutter-io.cn: a different hosted URL invalidates
  # pubspec.lock and re-resolves packages upward (material_ui 1.5.0 -> 1.11.0 breaks the
  # build with "MaterialShapes is imported from both"). pub.dev answers from here; only the
  # Flutter engine artifacts need the mirror.
  export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
  export RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER:-https://mirrors.ustc.edu.cn/rust-static}"
  export RUSTUP_UPDATE_ROOT="${RUSTUP_UPDATE_ROOT:-https://mirrors.ustc.edu.cn/rust-static/rustup}"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# ~/.work/toolchain/bin first: create-dmg shim maps the npm --dmg-title onto --volname
export PATH="$HOME/.work/toolchain/bin:/opt/homebrew/opt/flutter/bin:/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"

mkdir -p "$ANDROID_USER_HOME" "$GRADLE_USER_HOME" "$PUB_CACHE"

# Named prerequisites, checked before the first expensive step: a machine that lacks one
# fails here with the tool's name instead of halfway through a build.
need() {
  local tool=$1 hint=$2
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool is required ($hint)" >&2
    exit 1
  fi
}

host_guard() {
  # Flutter desktop builds are host-native: no cross-compiling for linux/windows.
  local want="$1" os
  os=$(uname -s)
  case "$want:$os" in
    linux:Linux|windows:*MINGW*|windows:*MSYS*|windows:CYGWIN*) ;;
    linux:*)   echo "error: Linux bundles must be built on Linux (Flutter has no cross-compile). Use CI." >&2; exit 1 ;;
    windows:*) echo "error: Windows bundles must be built on Windows. Use CI." >&2; exit 1 ;;
  esac
}

# The core is a c-shared library, not a downloaded executable: it is loaded into the app's
# own process and given the tun descriptor there, so there is nothing to spawn and nothing
# to inherit across exec. build/xray-lib.sh produces it — BUILD.md says how — and nothing
# here fetches a binary over the network any more, nor rebuilds one that is already there.
#
# A digest is optional, and off by default: a library built from a working tree changes with
# every change to it, so a pinned value would have to move on every change too. Set
# XRAY_LIB_SHA256 when the library comes from somewhere fixed — a CI artifact, a release
# tarball — and a different file fails the build instead of shipping inside an APK.
XRAY_LIB="android/app/src/main/jniLibs/arm64-v8a/libxray.so"
XRAY_LIB_SHA256="${XRAY_LIB_SHA256:-}"

xray_digest() {
  # GNU coreutils on Linux, shasum on the Mac; both print "<hash>  <file>". Either is
  # enough — requiring one spelling would fail on the other host for no reason.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Only asked for when a library actually has to be hashed: an unverified one needs no digest
# tool, and the check must not veto a build that does not verify anything.
need_digest_tool() {
  if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    return 0
  fi
  echo "error: sha256sum or shasum is required (verifies the Xray library digest)" >&2
  exit 1
}

# The library is an input to the APK, not something this script produces: build/xray-lib.sh
# does that, and it is not run from here because building the core needs a Go toolchain and
# a NDK that a machine packaging a release may not have. What is checked is that the file is
# there, and — when a digest is stated — that it is the one expected.
ensure_xray_lib() {
  if [ ! -f "$XRAY_LIB" ]; then
    cat >&2 <<EOF
error: $XRAY_LIB is missing.

The portal's core is that library; there is no executable to download any more. Build it
with build/xray-lib.sh (see BUILD.md, "Android APK") and leave the result at

  $XRAY_LIB

An APK packaged without it installs and runs, and every start fails with
"xray is not available in this build".
EOF
    return 1
  fi
  # Unset means "whatever build/xray-lib.sh produced": see the note next to XRAY_LIB_SHA256.
  if [ -z "$XRAY_LIB_SHA256" ]; then
    echo "xray: using $XRAY_LIB (no digest pinned)"
    return 0
  fi
  need_digest_tool
  local got
  got=$(xray_digest "$XRAY_LIB")
  if [ "$got" != "$XRAY_LIB_SHA256" ]; then
    cat >&2 <<EOF
error: $XRAY_LIB is not the library this build pins.
  expected: $XRAY_LIB_SHA256
  got:      $got

Either the library was rebuilt, in which case XRAY_LIB_SHA256 moves in the same commit, or
it came from somewhere else, which is a decision to make on purpose rather than to ship.
EOF
    return 1
  fi
  echo "xray: $XRAY_LIB matches $XRAY_LIB_SHA256"
}

case "${1:-get}" in
  get)        need flutter "Flutter SDK"; flutter --version; flutter pub get ;;
  macos)      need flutter "Flutter SDK"; need xcodebuild "Xcode command line tools"
              APP_ENV=stable; dart setup.dart macos --env "$APP_ENV"
              ls -lh build/macos/Build/Products/Release/*.dmg 2>/dev/null || true ;;
  apk)        need flutter "Flutter SDK"
              ensure_xray_lib || exit 1
              dart setup.dart android --env stable
              ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true ;;
  linux)      host_guard linux;   need dart "Dart SDK"; need flutter "Flutter SDK"
              dart setup.dart linux --env stable ;;
  windows)    host_guard windows; need flutter "Flutter SDK"
              dart setup.dart windows --env stable ;;
  ios)        cat >&2 <<'EOF'
error: this tree has no ios/ target — FlClashX ships android/macos/linux/windows only.

To enable iOS:
  1. flutter create --platforms=ios .
  2. verify every plugin has an iOS implementation (rust_api helper and the gomobile core are the risk)
  3. build on macOS:  flutter build ios --release   (needs an Apple Developer account for signing)
Unsigned builds do not install on non-jailbroken devices; TestFlight is the realistic distribution.
EOF
              exit 1 ;;
  run-macos)  APP=$(ls -d build/macos/Build/Products/Release/*.app | head -1); open "$APP" ;;
  *) echo "usage: $0 {get|macos|apk|linux|windows|ios|run-macos}" >&2; exit 2 ;;
esac
