# Portal pipeline: patches in, installers out

Portal is **FlClashX upstream + a numbered patch set**. Patches are public; users are not
expected to build anything — CI produces installers and attaches them to the GitHub release.

## Why patches, not a drifting fork

FlClashX moves. A fork that accumulates its own commits has to be merged by hand every time
upstream changes. A numbered patch set gives:

- one-command upstream update (`fetch upstream` → `./apply.sh` → build);
- a reviewable diff: every difference from stock FlClashX is a file you can read;
- a hard failure when a patch no longer applies, instead of a silently wrong merge.

`patches/*.patch` is the source of truth. Never edit the working tree and forget the patch.

## Layout

```
portal/                    working tree (fork remote: saved-j/portal)
├── apply.sh               apply / check / verify / upstream-log
├── release.sh             tag → push → CI builds installers
├── patches/               the whole difference from upstream
│   └── 0001-core-*.patch
└── docs/
    ├── PIPELINE.md        this file
    └── DPI.md             DPI evasion design
```

## Daily loop

```bash
cd ~/.work/portal
./apply.sh check          # do the patches still apply to the current tree?
./apply.sh                # clean upstream checkout + every patch → ~/.work/portal-work
./apply.sh verify         # prove patches reproduce this tree (ignores pipeline files)
./build.sh get && ./build.sh macos
```

Updating from upstream:

```bash
git fetch upstream
git checkout -B portal upstream/main
./apply.sh check          # if a patch conflicts, rebase it here — not in the tree
```

## Building per platform

| Target | Command | Where it can run |
|---|---|---|
| macOS | `./build.sh macos` | any Mac with Xcode |
| Android | `./build.sh apk` | any Mac with SDK + NDK (NDK is only needed by the gomobile core) |
| Linux | `flutter build linux --release` | **Linux host only** — Flutter desktop builds are host-native |
| Windows | `flutter build windows --release` | **Windows host only** |
| iOS | — | no `ios/` target exists in the tree yet; needs `flutter create --platforms=ios` plus signing |

Cross-building Linux from macOS or Windows from macOS is not supported by Flutter. That is why
the release matrix runs on CI runners (`ubuntu-24.04`, `windows-2022`, `macos-26`), not on one Mac.

## Release

```bash
./release.sh v0.1.0        # tags, pushes, CI builds linux/windows/macos/android
```

CI (`build.yaml`) runs `dart`, `plugins`, `go`, `rust`, `android`, `desktop` (linux/windows/macos)
and `upload`. The `upload` job has `contents: write` and attaches every artifact to the release,
then `publish.yaml` can re-run AUR/announcement steps without rebuilding.

Result for a user: open Releases, download the file for their OS, run it. No toolchain, no patches,
no build steps. The patch set stays public for review and for anyone who prefers to rebuild.

## iOS

There is no `ios/` directory: FlClashX ships android/macos/linux/windows only. Adding iOS means
creating the platform target, checking every plugin for an iOS implementation (the Rust helper and
the gomobile core are the risky ones), and an Apple Developer account for signing. Unsigned builds
cannot be installed on a non-jailbroken device, so "download and run" is not possible for iOS —
TestFlight is the realistic distribution path.

## Rules that keep this reproducible

1. Do not commit `pubspec.lock` churn caused by the China mirror (`pub.flutter-io.cn`). It rewrites
   hosted URLs and would break upstream CI. Revert it before committing.
2. `core/go.sum` must carry the checksums of the replaced modules; a build without them fails.
3. Machine-level mirrors (rustup, crates.io) belong in tool config, not in the repo.
