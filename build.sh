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
# China mirrors: pub/flutter engine (flutter-io.cn), rustup (USTC), crates.io (USTC via ~/.cargo/config.toml).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.work/.android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.work/.gradle}"
export PUB_CACHE="${PUB_CACHE:-$HOME/.work/.pub-cache}"
# Do NOT point PUB_HOSTED_URL at pub.flutter-io.cn: a different hosted URL invalidates
# pubspec.lock and re-resolves packages upward (material_ui 1.5.0 -> 1.11.0 breaks the
# build with "MaterialShapes is imported from both"). pub.dev answers from here; only the
# Flutter engine artifacts need the mirror.
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER:-https://mirrors.ustc.edu.cn/rust-static}"
export RUSTUP_UPDATE_ROOT="${RUSTUP_UPDATE_ROOT:-https://mirrors.ustc.edu.cn/rust-static/rustup}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# ~/.work/toolchain/bin first: create-dmg shim maps the npm --dmg-title onto --volname
export PATH="$HOME/.work/toolchain/bin:/opt/homebrew/opt/flutter/bin:/opt/homebrew/bin:$HOME/.cargo/bin:$PATH"

mkdir -p "$ANDROID_USER_HOME" "$GRADLE_USER_HOME" "$PUB_CACHE"

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

# The child process is not stored in the repository: 33 MB of binary per ABI would bloat
# every diff. It is fetched once into jniLibs, where nothing but the app build reads it.
ensure_xray_android() {
  local dest="android/app/src/main/jniLibs/arm64-v8a/libxray.so"
  if [ -f "$dest" ]; then return 0; fi
  local work
  work=$(mktemp -d "${TMPDIR:-/tmp}/xray-fetch.XXXXXX")
  echo "fetching Xray 26.11.9 for android/arm64"
  curl -fL --retry 2 -o "$work/x.zip" \
    https://github.com/XTLS/Xray-core/releases/download/v26.11.9/Xray-android-arm64-v8a.zip || return 1
  mkdir -p "$work/out" "$(dirname "$dest")"
  unzip -q -o "$work/x.zip" -d "$work/out" || return 1
  cp -f "$work/out/xray" "$dest" && chmod 755 "$dest"
}

case "${1:-get}" in
  get)        flutter --version; flutter pub get ;;
  macos)      APP_ENV=stable; dart setup.dart macos --env "$APP_ENV"
              ls -lh build/macos/Build/Products/Release/*.dmg 2>/dev/null || true ;;
  apk)        ensure_xray_android || exit 1
              dart setup.dart android --env stable
              ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true ;;
  linux)      host_guard linux;   dart setup.dart linux --env stable ;;
  windows)    host_guard windows; dart setup.dart windows --env stable ;;
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
