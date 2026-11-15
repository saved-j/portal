# Portal 1.01a — replayable patch series

Frozen snapshot of the Portal (FlClashX fork) product tree, split into
path-disjoint, ordered groups that replay `base` -> `target` byte-for-byte.

- base sha:      `5b4d0669cd0105a7eb41078b17c36944bde7f044`
- base tree:     `2e2ceffbdb42420204c2dce7ff8b85925b76884a`
- head sha:      `873e0ede12f4cf9aa5cbccf18627498b0c992516`
- target tree:   `68b9b4eeca70fc5168513145068275ee0f8b6109`  (see `target-tree.txt`)
- changed paths: 209 (123 A, 84 M, 2 D), 44 binary
- patches:       10, each `git diff --binary --no-renames --full-index base..HEAD -- <group paths>`

Every changed path appears in exactly one patch: the series carries 209
`diff --git` headers over 209 unique paths, zero duplicates, zero gaps, so the
groups are also usable piecemeal and in any order.

## Groups

| # | file | paths | A | M | D | area |
|---|------|-------|---|---|---|------|
| 01 | `01-android-shell.patch`        | 5  | 1  | 4  | 0 | `android/app/build.gradle.kts`, `AndroidManifest.xml`, `MainActivity.kt`, `plugins/XrayPlugin.kt`, `android/common/.../strings.xml` |
| 02 | `02-core-xray.patch`           | 16 | 13 | 3  | 0 | `lib/core/`, `lib/plugins/xray.dart`, `assets/xray/`, `core/` (Go core, profile-base merge) |
| 03 | `03-ui-dashboard.patch`        | 9  | 2  | 7  | 0 | `lib/views/dashboard/` incl. `widgets/`, `lib/pages/home.dart` |
| 04 | `04-ui-profiles.patch`         | 10 | 2  | 8  | 0 | `lib/views/profiles/` (add, facts, lights), `lib/models/` incl. generated, `lib/providers/state/profile.dart` |
| 05 | `05-l10n.patch`                | 11 | 0  | 11 | 0 | `arb/` (en, ru, zh_CN), `lib/l10n/` incl. generated messages |
| 06 | `06-branding-icons.patch`      | 52 | 21 | 29 | 2 | `assets/images/`, android `res/mipmap-*` + `res/drawable-*` + `ic_launcher_background.xml`, macos `AppIcon.appiconset`, windows `app_icon.ico`, `tool/` (icon sources + generators) |
| 07 | `07-desktop-product-name.patch`| 6  | 0  | 6  | 0 | `windows/CMakeLists.txt`, `windows/runner/{main.cpp,Runner.rc}`, `linux/CMakeLists.txt`, `macos/Runner/Configs/AppInfo.xcconfig`, `macos/Runner.xcodeproj/project.pbxproj` (name + bundle id `io.portal.xfc`) |
| 08 | `08-docs-pipeline.patch`       | 17 | 15 | 2  | 0 | `docs/`, `test/` (13 files), `apply.sh`, `build.sh`, `release.sh`, `setup.dart` |
| 09 | `09-pipeline-archive.patch`    | 68 | 68 | 0  | 0 | `pipeline/` as frozen in the target: `0.01a/`, `0.02/`, `CURRENT` |
| 10 | `10-misc.patch`                | 15 | 1  | 14 | 0 | `lib/common/`, `lib/providers/` (state, generated), `lib/ui/null_status.dart`, `lib/views/{about,hotkey}.dart`, `pubspec.yaml` |

Split notes: android `res/` bitmaps and the launcher XMLs are icons, so they sit
in 06 rather than 01; the Go core (`core/`) ships the same xray/profile work as
`lib/core/`, so it sits in 02; the macos `AppInfo.xcconfig` + `project.pbxproj`
changes are product name / bundle id, not art, so they sit in 07; `pipeline/`
is the archive of the previous series (about 56 MB of it), split out of 08 so
the docs/tests patch stays reviewable.

## Apply

```sh
git clone <origin> portal && cd portal
git checkout 5b4d0669cd0105a7eb41078b17c36944bde7f044   # else: git fetch origin <sha>
for p in pipeline/1.01a/patches/*.patch; do
  git apply --binary --whitespace=nowarn "$p"
done
```

`git apply` order does not matter: the groups are path-disjoint, so no patch
depends on another. `--binary` is what makes the 44 PNG/DAT/ICO blobs round-trip
byte-for-byte.

## Verify (1-in-1 by hash)

```sh
git add -A
test "$(git write-tree)" = "68b9b4eeca70fc5168513145068275ee0f8b6109" && echo MATCH
```

`git write-tree` is content-hash equality of the whole tree, so a MATCH means
every path, mode and blob — binaries included — is identical to the target.

Verified twice from clean clones of `base` (`git clone` + `git checkout base`):
patches applied forward (`ls`) and in reverse order (`ls -r`); both give
`68b9b4eeca70fc5168513145068275ee0f8b6109`, with plain `git add -A` and with
`git add -A -f`. 0 rejects, 0 fuzz.

## Self-reference caveat

Group 09 restores `pipeline/` exactly as it exists in the frozen tree — which
still holds the *previous* 1.01a attempt (8 patches, old target `2fb53694`), the
old `README.md` and old `target-tree.txt`. A patch file cannot contain its own
final bytes, so the regenerated series you are reading necessarily differs from
the copy that the series itself writes back. Apply-and-hash is the authority:
applying the ten files in this directory to a clean `base` clone reproduces
`68b9b4ee` exactly, and that is the check above.

The superseded 8-patch series was moved to Trash, not deleted in place.
