# Portal 1.02a — full series, patches 01–24

The behaviour half of the series: per-core server selection, a transactional mode switch, the
simple portal's core at cold start, a redaction boundary in the log, the rate feed the speed
widget draws from, and a three-state read of the engine's format file.

The build half: manifest backup/export hardening, the pinned Xray archive digest, the Gradle
wrapper and BUILD.md, minSdk from the version catalog, rpm Version/Release, packaging names,
AppImage branding and a trilingual README.

The transport and l10n half: a cancellable TCP sweep, a signing gate for the macOS DMG, opt-in
build dependencies, an Xray subscription parse result, a visible warning when connections cannot
be reset, a non-blocking Xray start, a linear sort, dead code removal, and localized About and
filter labels.

`NOTES-07-14.md` holds the per-patch notes for the build half.

- base: `873e0ede` (the proven 1.01a product)
- tree after `01`–`24` applied in order: `6e0da8985b2354e525d4166794493009315c890f`
- `flutter analyze lib/`: 0 errors, 12 warnings, all 12 present at the base
- `dart run intl_utils:generate` on the patched tree: no drift
- apply mode: `git apply` (plain diffs; one binary file, `gradle-wrapper.jar`, carried as a GIT binary patch)
- 24 patches, 47 files touched

## Groups

| # | patch | files | what it changes |
|---|---|---|---|
| 01 | `01-portal-selection-per-core.patch` | `lib/models/config.dart`, `lib/models/generated/config.{freezed,g}.dart`, `lib/views/dashboard/portal_controls.dart` | two persisted picks: `portalSelectionRules` (filter → server) and `portalSelectionXray` (the child's node); writers and readers on both lists; a tap in the simple portal restarts the child instead of calling `changeProxy` |
| 02 | `02-portal-switch-transactional.patch` | `lib/views/dashboard/portal_controls.dart`, `arb/intl_{en,ru,zh_CN}.arb`, `lib/l10n/**` (regenerated) | the mode switch becomes one transaction with rollback and a visible reason |
| 03 | `03-cold-start-child-core.patch` | `lib/providers/action.dart`, `lib/providers/actions/setup.dart`, `lib/providers/generated/action.g.dart` | cold start in the simple portal also starts Xray on the stored server; idempotent |
| 04 | `04-log-redaction.patch` | `lib/common/print.dart`, `lib/models/profile.dart` | one redaction boundary, non-throwing; userinfo and decoded provider headers stop being printed |
| 05 | `05-traffic-rate-feed.patch` | `lib/views/dashboard/portal_controls.dart` | the live rate is taken from the traffic sample instead of per-connection fields nothing fills |
| 06 | `06-engine-format-read-status.patch` | `lib/views/dashboard/portal_controls.dart` | a YAML read fault is no longer collapsed into `false`: `ok` / `parseFailed` / `empty`, with the reason logged |

## What each patch settles

**01 — one pick per core, because the two lists are different builds of one subscription.**
`AppSettingProps` gains `portalSelectionRules` (`Map<String, String>`, filter → server) and
`portalSelectionXray` (`String`), next to the two sort fields that exist for the same reason;
`lib/models/generated/config.*` is the build_runner output for that change and nothing else
(re-running `build_runner` on the patched tree rewrites nothing). `PortalSelectionNotifier`
reads both and owns both writes, so the field is never written without a reader:

- the rules list highlights the engine's own selection (`pending` → `chosenName`) and falls
  back to its stored pick when the engine reports nothing — a fresh start, or a return from
  the simple portal;
- the simple portal highlights `portalSelectionXray`, and only when that name is in the list
  the child actually offers;
- a tap in the simple portal stores the pick and restarts the child on that server
  (`XrayServerConfig` is passed down to the row for this); it never calls `changeProxy` — the
  engine has no such proxy and its route already points at the local socks;
- `_enterSimplePortal` reads the stored pick first, so a switch back into the simple portal
  returns to the node the owner chose, not to whatever the engine's names would resolve to;
  it writes back the node it really started, so a fall-through to the first server becomes
  the stored pick.

**02 — the switch is a transaction, not a hopeful sequence.**
`_switchPortal` goes in one order: close the portal, stop the previous core, start the next
one, wait for the engine to have taken the mode, move the route, ignite the portal. Each step
is awaited and checked; a failure calls `_rollBackPortal` (previous mode, previous core,
previous run state, best effort) and `_reportSwitchFailure`. The failure text is
`portalSwitchFailed` in `arb/intl_{en,ru,zh_CN}.arb`, shown through `dialogs.showNotifier` at
`MessageLevel.error`, with the child's own last line or the engine's own complaint as
`{reason}`. `_enterSimplePortal` no longer returns silently on a dead child: it throws
`_PortalSwitchFailure`, which is what makes a rollback possible at all. A second tap while a
switch is in flight is dropped, not queued.

es/fr/ja/ko have no `portalSwitchFailed` and fall back to the English text — the three
localisations asked for are the three that exist.

The `lib/l10n/**` diff is large because `intl_utils` renumbers every `m<nn>` slot when one
message is inserted in the middle of its union list; the numbering is the generator's, not a
hand edit (re-running `intl_utils:generate` on the patched tree rewrites nothing).

**03 — cold start brings up the core the saved mode needs.**
`SetupAction._start` already brought mihomo up; in the simple portal the engine is only a pipe
whose global selector points at `127.0.0.1:10808`, so a start that stopped there sent
everything into a dead port. `_startSavedPortalChild` runs after the tun is up, in both the
cold-start branch and the open-the-portal branch, and only when the saved mode is `global`:
it starts the child on `portalSelectionXray` (falling back to the panel's first server), then
points `GLOBAL` at `XRAY-SOCKS` exactly as a live switch does. Idempotent twice over: a
`_startingChild` flag for overlapping calls, and a running/`status()` check so a child that is
already up is left alone. A failure is logged with the child's last line and changes nothing.

**Dependency, stated plainly:** 03 reads `portalSelectionXray`, which 01 introduces. It
applies to `873e0ede` textually on its own (verified below) but compiles only with 01 in the
tree. Patch order is compile order; 03 is not meant to be used without the pick it reads.

**04 — one redaction boundary, and it cannot throw.**
`redactLogText` in `lib/common/print.dart` washes every line before it is printed or filed:
the whole query of any `http(s)` URL, bare UUIDs, and the value of `token|uuid|password|
passwd|pwd|secret|apikey|authkey|authtoken|access_token|api_key|key|auth` after `=` or `:`.
Case-insensitivity is a `caseSensitive: false` argument, never an inline `(?i)` flag — Dart's
`RegExp` throws `FormatException` on those. The function has its own `try`, `log()` has its
own `try` around the sink, and both degrade to a fixed notice instead of throwing: a printer
called from core callbacks and timers has nobody above it to catch. `Profile._updateFrom`
stops printing `subscription-userinfo` and the decoded provider headers; the line keeps which
headers arrived and how long their values are.

**05 — the feed, not the widget.**
`SpeedCard`/`NetworkSpeedCard` in `lib/views/dashboard/widgets/traffic.dart` were never
touched. The live numbers were fed by `portalLiveProvider`, which summed
`TrackerInfo.downloadSpeed`/`uploadSpeed` — fields the engine's connection snapshot does not
carry and nothing in the app writes (the only speed computation lives in
`lib/features/connection/tracker_speed_ranker.dart`, inside the connections table). The sum
was therefore a hard zero however fast the wire moved, which is what the owner saw: a portal
with no rate on it. The rate now comes from the traffic sample the speed widgets already draw
(`trafficsProvider`, `Core.getTraffic` once a second), and the connection count still comes
from the connection list. The portal and the cards now show the same number.

**06 — a corrupt file is not an empty one.**
`engineFormatAvailableProvider` collapsed a read fault and an absent file into `false` through
`catch (_)`. `engineFormatStatusProvider` returns `EngineFormatStatus.{ok, parseFailed, empty}`
and logs `engine format read failed: <reason>` at warning level through `commonPrint`, which
is the log path the core's own faults already use. The switch's enable rule is unchanged
(`ok` only), so the UI does not move; only a corrupt subscription is now distinguishable from
one the panel never served.

## Verify

```
fresh worktree at 873e0ede, each patch alone:      git apply --check  ok   git apply  ok
  01  4 files   02  12 files   03  3 files   04  2 files   05  1 file   06  1 file
fresh worktree at 873e0ede, 01…06 in order:        applied, no conflicts
flutter pub get                                    Got dependencies
flutter analyze lib/                               0 errors, 12 warnings (the same 12 as 873e0ede)
build_runner build --delete-conflicting-outputs    rewrites nothing
intl_utils:generate                                rewrites nothing
git add -A && git write-tree                       bb71c61ea8383e44f8b7f84a4417aa39ac330099
```

An in-package probe (`flutter test`, a temporary file, since removed) confirmed the redaction
on six shapes: a subscription URL's query, `{"token": "…"}`, `Token=…  Password: …  key=…`, an
upper-case UUID, a plain line, and the empty string.

## Not done here, on purpose

- No APK build, no install, no device run, no push: this series is text and analysis only.
- No reformatting: every diff touches only the lines its finding names.
- 05 changes the feed only. If a rate is still absent on device after this, the next suspect is
  `_refreshRunningState` in `lib/providers/actions/setup.dart`, which is the only caller of
  `updateTraffic` — untouched here because nothing in the code proves it wrong.
