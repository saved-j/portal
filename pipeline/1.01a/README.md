# Portal 1.01a — replayable patch series

Frozen snapshot of the Portal (FlClashX fork) tree, split into path-disjoint,
ordered groups that replay `base` → `target` byte-for-byte.

- base sha:        `5b4d0669cd0105a7eb41078b17c36944bde7f044`
- base tree:       `2e2ceffbdb42420204c2dce7ff8b85925b76884a`
- head sha:        `d1d4f22a8e1f5517b3c077ac511e4152171bd311`
- target tree:     `2fb536946ab6e0a017d640d8730ff001a4166780`  (see `target-tree.txt`)
- changed files:   193 (113 A, 78 M, 2 D), 44 binary
- patches:         8, `git diff --binary --no-renames --full-index base..HEAD -- <paths>`

Every changed path appears in exactly one patch (verified: 193 diff headers,
193 unique paths, zero duplicates), so groups can also be applied piecemeal.

## Groups

| # | file | files | area |
|---|------|-------|------|
| 01 | `01-android-shell.patch`  | 5  | `android/app/src/main/kotlin/`, `AndroidManifest.xml`, `android/app/build.gradle.kts`, shared `strings.xml` |
| 02 | `02-core-xray.patch`     | 16 | `lib/core/`, `lib/plugins/`, `assets/xray/`, `core/` (Go core: profile-base merge) |
| 03 | `03-ui-dashboard.patch`  | 8  | `lib/views/dashboard/` (+ widgets) |
| 04 | `04-ui-profiles.patch`   | 10 | `lib/views/profiles/`, `lib/models/`, `lib/providers/state/profile.dart` |
| 05 | `05-l10n.patch`          | 11 | `arb/`, `lib/l10n/` |
| 06 | `06-branding-icons.patch`| 52 | `assets/images/`, android res icons (mipmap/drawable), macos AppIcon + pbxproj + AppInfo.xcconfig, windows ico, `tool/` |
| 07 | `07-docs-pipeline.patch` | 75 | `docs/`, `pipeline/` (0.01a, 0.02, CURRENT), `apply.sh`, `build.sh`, `release.sh`, `setup.dart`, `test/` |
| 08 | `08-misc.patch`          | 16 | `lib/common/`, `lib/pages/`, `lib/providers/`, `lib/ui/`, `lib/views/about.dart`, `lib/views/hotkey.dart`, `pubspec.yaml` |

## Apply

```sh
git clone <origin> portal && cd portal
git checkout 5b4d0669cd0105a7eb41078b17c36944bde7f044   # must resolve; else fetch the sha
# or, if the repo is shallow: git fetch origin 5b4d0669cd0105a7eb41078b17c36944bde7f044
for p in pipeline/1.01a/patches/*.patch; do git apply --binary --whitespace=nowarn "$p"; done
```

`git apply` order matters only in the sense of reading the series top-down; because
the groups are path-disjoint, the patches do not depend on each other.

## Verify (1-in-1 by hash)

```sh
git -C . add -A -f       # -f: plugins/proxy/windows/.vscode/settings.json is tracked but gitignored
test "$(git write-tree)" = "2fb536946ab6e0a017d640d8730ff001a4166780" && echo MATCH
```

`-f` is required — the base tree contains that one ignored-but-tracked file, so a plain
`git add -A` drops it and the tree hash diverges.

Verified in a clean export of `base` (`git archive base | tar -x`): all 8 patches applied
clean, `git add -A -f && git write-tree` = `2fb536946ab6e0a017d640d8730ff001a4166780`,
identical to the target. Binary blobs round-trip via `--binary` (tree equality is
content-hash equality, so every PNG/DAT/ICO is byte-identical).
