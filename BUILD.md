# Building Portal from a clean clone

The goal: `git clone`, run one command, get the same application that is installed on the
author's phones. This file lists the exact toolchain, because several build steps are
pinned and a floating version will change the output.

## Pinned toolchain

| tool | version | why pinned |
|---|---|---|
| Flutter | **3.47.9** (stable, revision `c197ca5199`) | engine/AOT output differs between versions |
| Dart | bundled with Flutter 3.47.9 | `pubspec.lock` is committed |
| JDK | **17** | Gradle 9.8 + AGP in `android/gradle/libs.versions.toml` |
| Gradle | **9.8.0** (`android/gradle/wrapper/gradle-wrapper.properties`) | wrapper committed |
| Android compileSdk / targetSdk | **37** | `libs.versions.toml` |
| Android NDK | **28.2.13676358** | native pieces of the plugins |
| Go | **1.27.0** | `core/go.mod` (`go 1.27.0`), built by the `setup` build hook |
| Rust | **1.99.0** (`plugins/rust_api/rust/rust-toolchain.toml`) | `rust_api` hook |

China mirrors are optional and only affect download speed; they do not change the output.

## Commands

```bash
git clone https://github.com/saved-j/portal.git
cd portal

# everything the build needs, in one place
export JAVA_HOME=/path/to/jdk-17
export ANDROID_HOME=/path/to/android-sdk          # needs platform 37 + NDK 28.2.13676358
export PATH="$PATH:/path/to/flutter/bin:$HOME/.cargo/bin:/path/to/go/bin"

./build.sh get
./build.sh apk
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`build.sh` falls back to the author's macOS paths only when these variables are unset; on
any other machine set them explicitly.

## Signing — read this

`android/app/build.gradle.kts` signs a release APK with `android/app/keystore.jks` plus
`storePassword` / `keyAlias` / `keyPassword` from `android/local.properties`. **Neither the
keystore nor the passwords are in this repository** — a keystore is the app's identity and
must never be published.

What that means:

- building without a keystore still works, but Gradle falls back to the **debug** key and
  adds the `applicationIdSuffix ".dev"`, so the APK installs side by side with the release
  build instead of replacing it;
- the code, resources, native libraries and assets are the same in both cases — the
  difference is the signature (and the package name of the fallback build).

So "the same APK" means: same sources, same toolchain, same application content. A byte
identical file additionally requires the author's signing key, and APK bytes are also
affected by zip timestamps, which no build system reproduces across machines.

## What to compare if you want to convince yourself

```bash
unzip -o build/app/outputs/flutter-apk/app-arm64-v8a-release.apk -d /tmp/ours
shasum -a 256 /tmp/ours/classes.dex \
             /tmp/ours/lib/arm64-v8a/*.so \
             /tmp/ours/assets/flutter_assets/kernel_blob.bin 2>/dev/null
```

Compare those hashes with the same files from the APK you already have: they are the parts
the toolchain produces from this source, and they should match when the pinned versions are
used.

## The patch pipeline

`pipeline/1.01a` is a single frozen series against upstream FlClashX
(`5b4d0669`). `./apply.sh 1.01a verify` clones the upstream base, applies the nine groups
and proves by tree hash that the result equals the product tree the series declares.
