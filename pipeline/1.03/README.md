# Portal 1.03 — point fixes on top of 1.02a

Base: 1.02a applied to 873e0ede (tree `f8044d71`). Each patch here is a single defect found on
the device, not a redesign.

- `01-simple-mode-tun-config-schema` — the tun inbound refused the whole document:
  `autoSystemRoutingTable` is a `[]string` of routes in this core, not a flag, so the child
  exited 23 before it ever read the tunnel descriptor. The key is omitted; the VpnService owns
  the routes. Evidence: `XrayCore: failed to load inbound detour config for protocol tun >
  json: cannot unmarshal bool into Go struct field TunConfig.autoSystemRoutingTable of type
  []string`.
- `02-child-start-serialised` — the mode switch and a row tap both called start, and the plugin
  answered the second by cancelling the first: `start cancelled by a newer request` in a loop
  with no child running. Starts are serialised in `XrayCore`; a stop waits for the start it is
  about to cancel.
- `03-xray-in-process-jni` — the core cannot be a child at all: `Runtime.exec` spawns through
  `posix_spawn` with close-on-exec on, so the tun fd never crossed the boundary and the child
  died with `failed to start proxy > bad file descriptor` without ever printing
  `read Android Tun Fd`. The plugin loads the c-shared library into its own process
  (`System.loadLibrary("xray")`, guarded so a build without it answers
  `xray is not available in this build`), declares the three JNI entry points, writes the same
  `xray-tun.json` with `log.error` inside filesDir and `loglevel: info`, calls
  `XrayStart(document, tun.fd)` on the background executor, and reports a non-null return as
  the core's own error text. `XrayStop()` replaces `destroy()`: a stop takes the operation
  token first, so a queued start cannot win, and the native call is queued on the executor so
  the caller is not held for the core's wind-down. A start is now also recognised by the
  `running` flag, because an in-process core has no exit code to watch.
- `04-xray-tun-ack-from-log` — with no stdout left to drain, the acknowledgement is the core's
  own log line: the tun reader's start line, or `read Android Tun Fd`. A `[Error]`/`[Fatal]`
  line fails the start at once with that text instead of sitting out the deadline; the
  deadline stays as the backstop, the log is tailed by offset rather than re-read, and the
  poll sleeps in 50 ms slices so a newer operation token ends the wait immediately.
- `05-xray-lib-packaging` — `build.sh` no longer downloads the Xray executable into jniLibs.
  The library is built by `build/xray-lib.sh` (BUILD.md documents how and does not duplicate
  it); packaging checks that it is present, verifies `XRAY_LIB_SHA256` when one is pinned, and
  leaves the geo assets and their Flutter asset directory untouched. `jniLibs` keeps
  `useLegacyPackaging = true`, which stores the `.so` uncompressed and extracts it to
  `nativeLibraryDir` — the layout `System.loadLibrary` and Flutter's ABI lookup both expect.
- `06-await-ack-return` — the acknowledgement's timeout path fell out of the loop without
  returning anything, so a start that never reached the core reported nothing at all.
- `07-xray-asset-dir-argument` — the core resolves `geosite:`/`geoip:` against
  `os.Executable()`, which inside an app is `/system/bin`
  (`common/geodata: failed to open geosite.dat > stat /system/bin/geosite.dat`). `XrayStart`
  takes the asset directory as its third argument and sets `xray.location.asset` in the
  library's own process before the core is created; a JVM `setenv` is not reliably visible to
  an already-loaded Go runtime.
- `08-tun-config-no-interface` — every start after 07 died with `app/proxyman/inbound: failed
  to start proxy > route ip+net: netlinkrib: permission denied`. `autoOutboundsInterface` makes
  proxy/tun resolve the interface with `net.InterfaceByName`, i.e. a rtnetlink `RTM_GETLINK`
  read Android denies to an app uid. The key is gone, together with the plumbing that fed it
  (`XrayTun.interfaceName`, `outboundInterface()`, the "no interface, no start" veto), and the
  service adds its own package to `Builder.addDisallowedApplication`: the VPN installs no route
  into the tun for this uid, which is the per-uid exclusion `VpnService.protect` makes for one
  socket and the Android-native substitute for binding outbounds to an interface. Access
  control no longer puts this app on the allow list either — a uid cannot be on both, and this
  one has to stay outside.
- `09-tun-descriptor-verified` — the next refusal was `app/proxyman/inbound: failed to start
  proxy > inappropriate ioctl for device`, and it was a number, not a path: proxy/tun's Android
  reader takes the number from `xray.tun.fd`, sets it non-blocking and duplicates it, and never
  ioctls what it was given until `Name()`. A closed `ParcelFileDescriptor` reports -1, the
  library unset the variable, and proxy/tun fell back to fd `0` — stdin. The plugin refuses a
  number below 3, drops a cached tunnel whose descriptor closed and waits for the service's
  next publish; the service takes a published tunnel down before publishing the next one. The
  library checks the descriptor with `Fstat` + `TUNGETIFF` before starting the core — `IFF_TUN`
  set, no virtio header — and names it in logcat under the `libxray` tag.
- `10-core-log-into-logcat` — the shipped build is not debuggable, so `run-as ... cat
  files/xray.log` answers `package not debuggable` and the core's own record was unreadable on
  the device. Every line the start's tail reads is repeated under `XrayCore` with a `core:`
  prefix.
- `11-tun-settings-four-keys` — the tun settings are `name`, `mtu`, `gateway`, `dns` and
  nothing else. `autoSystemDnsToGateway` is validated by `infra/conf/tun.go` and can never be
  honoured on Android (no `ConfigureSystemDNS` in the Android reader);
  `autoSystemRoutingTable` must never be emitted (a `[]string` in this schema, and a non-empty
  value implies `autoOutboundsInterface: auto`); `name` must stay non-empty or
  `GetAvailableTunName()` calls `net.Interfaces()` at config build, the same denial one step
  earlier.
- `12-tun-descriptor-duplicated` — the core is handed `tun.descriptor.dup()`, closed once the
  native call returns (proxy/tun duplicates what it is given), and both places that decide to
  use a tunnel ask `descriptor.fileDescriptor.valid()` rather than only `fd >= 3`: a number can
  be reused by the next file the process opens. The library returns an error for a number below
  3 instead of unsetting the variable.
- `13-ack-tun-up-line` — the acknowledgement is `<name> up` from
  `proxy/tun/handler.go`, printed once the stack, the inbound and the reader are running.
  `read Android Tun Fd` looks like proof and is not: it is written before the descriptor is
  validated, and both inbound refusals on the device came after it.
- `14-selection-while-closed` — a row tap in the simple portal with the portal closed stores
  the pick and stops there: the highlight reads the same stored pick, and the next open starts
  that node. The restart path is unchanged for a running portal.
- `15-network-mode-reapplies-profile` — the simple portal pushes no engine config, so returning
  to the portal network left the engine with nothing applied: groups read empty and the core
  answered "Config is not applied". The return path applies the profile (forced) before asking
  for the mode and fails the switch with its own sentence if the profile is rejected.
- `19-simple-service-without-mihomo-listener` — the simple portal handed the child a duplicate
  of the tun while the engine kept reading the same interface: `_startSimplePortal` called
  `startListener`, which opens the engine's listeners and *then* asks the service for the
  tunnel, and neither `VpnService.handleStart` (which took a previous tunnel down only when
  `tunOwnedByChild`) nor `ServiceController.release()` (which skipped the Go stop when
  `xrayTunActive`) ever stopped a mihomo one. The service is now asked on its own —
  `CoreLib.startPortalService/stopPortalService` used by the simple start, stop, teardown and
  restart — `ServiceController.start` closes the engine's listener before it publishes the
  descriptor for the child, `release()` stops it unconditionally (Go `StopListener` is
  idempotent), and `handleStart` takes down any previous tunnel, whichever core owned it,
  before `establish()`. Expected on the device: `XrayCore: core: … portal0 up`, then no new
  `GoLog … tun-in` line and no `10808 connect error`; the network path is unchanged and
  `GoLog … tun-in` resumes when the portal returns to it. Rollback: reverse the patch — the
  engine reads the tunnel beside the child again.
- `19b-simple-portal-returns-to-the-engine` — 19 left the engine stopped in the simple portal,
  and the return path had been written for the opposite: it pushed the profile and waited for
  the engine to take `rule` *before* starting it, so the switch came back after 12 s with
  `the engine did not take rule within 12 s`, and every settings push answered
  `config is not applied` while nothing listened. The return now sets the mode, starts the
  run (whose own forced push applies the profile) and waits for the engine to have taken it
  after the start; `updateConfig` is a no-op in the simple portal and while no run exists,
  instead of pushing at an engine that has nothing to update. The same patch writes the
  hand-over into the log, so the transition is evidence and not an assumption:
  `tun generation=N owner=Xray previous=Mihomo stopped=true`, `tun generation=N owner=… released,
  owner=Off`,  `engine listener owner=Xray stop before the hand-over=ok`. Rollback: reverse 19b
  — the return switch times out again, 19 itself keeps the single reader.
- `19c-config-push-without-a-config` — with the engine not running between a stop and the
  next start (and never in the simple portal), a settings push raced the apply that gives the
  engine its config and the answer `config is not applied` was shown as an error
  (`[APP] message: config is not applied`) in the middle of a switch. That answer now means
  "nothing to update yet": the push that follows carries the settings, so the update is
  skipped instead of thrown. Rollback: reverse 19c; the line comes back, the switch itself
  still completes.

- `20-owner-generation-and-serialized-switch` — the tunnel had three owners and no record:
  a Dart flag around the mode switch, `ServiceController`'s mutex around the service start,
  and a row tap that called the child directly, each correct about its own step. `PortalRuntime`
  (`Off | Starting(g, owner) | Active(g, owner, fdEpoch) | Stopping(g, owner) | Failed(g, reason)`)
  is now the one record, and `PortalRuntimeCoordinator` the one entry: the power button, a row
  tap, Quick Settings, the quick action, a revoke and a restart are serialised under one mutex
  in the order **coordinator → transitionLock → ServiceController.lock → tunLock**. A revoke
  does not wait for that mutex — it mints a new generation (`PortalRuntimeState.revoke`) and
  the transaction in flight finds itself stale. `XrayStop` is waited for before a stop reports
  success, `XrayTunHolder` operations are locked and epoch-bound, `dup()` is reachable only
  through `XrayTun.duplicate()` (a closed descriptor answers `null`, never `Already closed`),
  and `Active` is published only after the owner acknowledged the tunnel — the child's
  `portal0 up`, or the engine's service. Expected record: `PortalRuntime generation=N owner=…
  phase=…` and `service phase=… generation=N`. Rollback: reverse 20; 19/19b/19c keep the
  single engine-free start.
- `20b-simple-portal-dns-hijack` — with a node the child's document carried the panel's own
  `dns` section, and nothing hijacked the tunnel's resolver: the core dispatched
  `198.18.0.2:53` to `direct` (`[tun-in -> direct] … 198.18.0.2:53`), so no name resolved and
  every request timed out (rc=28). A concrete node appeared to work, the balancer pick
  ('Авто-выбор') did not. The document is now rewritten — a `dns` section with a queryable
  server, one `dns` -protocol outbound (the document's own if it has one), and a first routing
  rule sending the tun inbound's port 53 to it. Chosen over rejecting the document, because a
  fallback would silently turn 'Авто-выбор' into "the first server". Expected:
  `[tun-in -> <dns outbound>]` for 198.18.0.2:53 and `http=200` by hostname, in both picks.
- `20c-portal-telemetry-files` — the core's log lived in `filesDir`, which `run-as` refuses on
  a release build: nothing could be read off the phone. The record now goes to the app's
  external files directory — `portal-status.log` (heartbeat every ~5 s: `owner= generation=
  fdEpoch= phase= engine= child= listeners= egress=`), `portal-transitions.log` (one line per
  transition, written from the record's own `onPublish` hook, so no entry can move the tunnel
  silently) and `xray.log` (the core's own log). `listeners` is measured — `/proc/self/net/tcp`
  where allowed, else a loopback handshake against the mixed port and the cores' defaults —
  and says `unknown` when neither could answer. Paths are constants in `PortalTelemetry.kt` and
  named in `BUILD.md`.
- `20d-server-list-never-empties` — a switch empties both row sources for a moment (the engine
  has no groups until it takes the profile, the child none until its subscription is read) and
  the list drew that as an empty subscription. Both the mode control and the list now keep the
  last non-empty group they drew and replace it only with a non-empty answer from the new
  owner; before anything answered, the profile's own `proxies:` are the rows; a profile with no
  proxies still ends in the honest empty state. No provider is read after an `await`, and no
  row depends on a config push.
- `21-switch-push-without-the-debounce` — a mode switch took ~15 s because its own config push
  went through `applyProfileDebounce`: the 2 s floor / 10 s ceiling an editor needs (measured
  off the last push's duration) held the engine's first config back while the owner watched a
  list nothing had filled. `applyProfileNow` cancels the pending debounced push and applies at
  once, unawaited, for the start of a switch; ordinary edits keep the debounce. Its failure is
  a log line and a notice, not a reason to take the portal down — the tunnel already has its
  new owner.
- `21b-switch-reads-the-acknowledgement` — `_awaitMode` waited up to 12 s for
  `inputsApplied()`, i.e. for the engine to have taken the profile its start pushed. That is a
  different question from whether the switch happened, and its answer is already the record's:
  `PortalRuntime.open` publishes `Active` only after the owner acknowledged its own listener or
  tunnel, and the start returns on that answer. The switch now reads the record, bounded at
  1.5 s as a guard against a record that never moves; a missing acknowledgement is a warning
  over the list and a log line, never a rollback.
- `21c-switch-timings-in-the-transition-log` — both halves of a switch are now measured from
  the tap into `portal-transitions.log`: `kind=switch phase=active duration_ms=…` written by
  the record's own `onPublish` hook (the tap stamped on the native side by a channel call), and
  `kind=switch phase=list duration_ms=… source=live|held|profile rows=…` written by the screen
  from its own stopwatch. `source=` is part of the answer: only `live` is the new owner's list;
  `held`/`profile` are what keeps the screen non-empty. `BUILD.md` documents the shape; the
  channel methods are `switchStart` and `switchTiming`.
- `22-server-list-follows-the-mode` — with the portal closed, a switch to 'Сеть порталов' kept
  the simple portal's rows ('Авто-выбор', 'Эстония', 'Финляндия', 'Германия' — the Xray
  document), and the transition log showed the same `rows=28` for both modes. The fallback
  parsed one source for both modes while `live` existed only while the engine ran. Now each
  mode reads only its own: the simple portal the profile's Xray document
  (`xrayServersProvider`), the network mode the engine's groups, and with the portal closed
  the engine's own last answer for this profile (`portalEngineRowsProvider`, filled from a
  `ref.listen`) and then the profile's engine-format `proxies:`. A group held from the other
  mode is dropped, and the list line carries `mode=` beside `source=`: `mode=rule source=live
  rows=28` / `mode=global source=live rows=3`. 20d's never-empty rule and the honest empty
  state (`source=none`) stand.
- `23-pings-are-real-or-dashes` — the portal's rows read 5/10/14/25 ms to Finland and Estonia
  from China. `tcpPing` connected to the node's *name*, the running core answered it with its
  fake-IP (`198.18.x.x`), and the handshake completed against the core's own listener: the row
  reported the phone's loop. `isTunnelOwnedAddress` refuses `198.18.0.0/15` (gateway
  `198.18.0.1`, resolver `198.18.0.2` included), loopback, `0.0.0.0` and link-local;
  `probeTcp` resolves the name itself and hands the handshake the resolved address, and a fake
  address, an unresolved name, a timeout or an unreachable route are all `ms == null` — a dash,
  never a number. The network mode keeps the engine's own delay for its rows and asks the
  engine for a test; only the simple portal is timed from here, against the node's real
  address. Every measurement logs what it timed: `portal delay Эстония: … → 198.18.0.5 is the
  tunnel's own address, no number` / `… → 185.155.222.6 214 ms`.
- `24-updater-points-at-saved-j-portal` — `constant.dart` still named
  `pluralplay/FlClashX`, and `asset.dart` asked that release for `FlClashX-android-$arch.apk`,
  `FlClashX-windows-$arch-setup.exe`, `FlClashX-macos-$arch.dmg`,
  `FlClashX-linux-$arch.{AppImage,deb,rpm}`. The repository is now `saved-j/portal` and the
  names are this project's: `Portal.apk` (arm64), `Portal_legacy.apk` (arm32),
  `Portal_x86-64.apk`, `Portal_universal.apk`, `Portal.exe`, `Portal.dmg`, and
  `Portal-*.AppImage|deb|rpm` matched against the release's own assets (an arch token in the
  name still has to match this device). `UpdateTarget.pick()` searches the release instead of
  building a URL from a guess; a release with nothing for this platform says so with the names
  it looked for (`noAsset`, detail `Portal.apk | Portal_universal.apk`, shown under the
  message), and no FlClashX file is offered in its place. The download logs
  `update: repository=saved-j/portal asset=Portal.apk url=…`.
- `25-a-row-belongs-to-its-owner` — 22 gave each mode its own source and the leak survived: the
  owner switched to 'portal network' with the portal closed and read the child's names again.
  `held` was a single Group (the simple portal's rows became `held`, then answered the network
  mode once its own `live` was null), and `live` was never checked against the owner (the
  engine's groups stay in memory after it stops, the child's servers exist with it stopped —
  the vivo showed `mode=global source=live` and `mode=rule source=live` while `phase=Off`). Now
  `live` counts only when the record's `Active` owner is the mode's (`portalStatusProvider`),
  `held` is kept per owner, and the transition line carries `owner=` and the first three
  `names=`, so a wrong list cannot pass silently.
- `26-version-0.5.3-portal-duo-2b` — release metadata only: `pubspec.yaml` carries
  `version: 0.5.3-portal-duo-2b+<code + 1>`, which is the one tracked source for the version
  (Flutter writes `android/local.properties` from it, `setup.dart` reads it for
  `--dart-define=APP_VERSION`, the About screen reads the installed package). `local.properties`
  is gitignored and was written on disk too. No behaviour change.

- `27-three-failed-fetches-take-the-mode-off` — the two documents a panel serves are counted
  apart (`lib/core/portal_feed.dart`): an attempt is counted where the fetch happens — `http
  502`, an unparsable body, a client config with zero servers, a throw — three failures in a
  row take the corresponding mode off, and that feed's own next success sets it back to 0 in
  the same run, no restart. Engine format gone: the network mode's switch and the split-tunnel
  filter strip are disabled with a localized reason. Node list gone: the switch refuses the
  simple portal with its own reason and the portal does not open in that mode. Both gone: both
  controls are disabled and the portal stays closed (`pickMode` and `_run` refuse, which is what
  covers the tray, a hotkey, Quick Settings and Always-on). Every attempt is written beside the
  transitions as `kind=availability feed=… attempts=n/3 state=…`. ru/en/zh_CN strings; version
  0.5.3-portal-duo-2c+2026111403.

- `28-engine-config-is-the-profile's-own` — the network mode's list was drawing `XRAY-SOCKS`
  (badge `SOCKS5`) under a `PORTAL-XRAY` group that no panel ever sent. It was not the profile
  and not a stale file: `lib/common/task.dart` injected both into **every** pushed engine config
  for a bridge design abandoned when the simple portal became its own core, and
  `lib/core/xray_bridge_config.dart` (the module that produced that shape, including the
  `GLOBAL` override) is called from nowhere. The injection is removed, the dead bridge module
  and its test are deleted, and the pushed document is exactly the profile's own `proxies:`,
  `proxy-groups:` and `rules:` — the list carries `VPN - Main`, `Auto Europe`, `Auto America`,
  `Auto Asia` and their members, and nothing else. Version 0.5.3-portal-duo-2d+2026111404.

Apply (to a tree that does not already carry the 01..02 commit):
```
git -C <clone> checkout -B work <1.02a commit>   # tree f8044d71
for p in pipeline/1.03/patches/*.patch; do git apply --whitespace=nowarn "$p"; done
```

- tree after 1.02a + 1.03 patches 01..02: `c3972a749849bacb5219421a98e4c4b4c1ad5a55`
- repo commit carrying 01..02: `5d4b8d77`
- tree after 1.02a + 1.03 patches 01..05: `aabe2839bc7cb7373ac261271b99d98affb9dc24`
  (5d4b8d77 + 03..05; only `XrayPlugin.kt`, `build.sh`, `BUILD.md` and
  `android/app/build.gradle.kts` move)
- tree after 1.03 patches 08..13: `b32e0858fea0764e4a3f6a4ed8351e0f0ef45f0f`
  (commits 9d33b922, e5bf21e4, 052141f0, fcad64e3, 993e1a77, f8e3d387; only `XrayPlugin.kt`,
  `XrayTun.kt` and `VpnService.kt` move — the library source lives outside this tree, see below)
- tree after 1.03 patches 08..15: `40db3c58f5b1536c28eeef2f250ea8c6cc9fed65`
  (commit `00bb44ed`); 14 and 15 move only `lib/views/dashboard/portal_controls.dart`
- tree after 1.03 patches 21..21c: `ea7ec87eac06e7933b8b64ce59184e49241a43b8`
  (pristine `5b6061ed` + 21, 21b, 21c applied in that order; the branch carries the same product
  files, plus `pipeline/`). 21 moves `lib/providers/actions/setup.dart`; 21b moves
  `lib/views/dashboard/portal_controls.dart`; 21c moves `BUILD.md`,
  `lib/plugins/portal_runtime.dart`, the new `lib/plugins/portal_switch_timing.dart`,
  the new `test/plugins/portal_switch_timing_test.dart`, `PortalTelemetry.kt` and
  `PortalRuntimePlugin.kt`, and adds the `switchStart`/`switchTiming` channel methods.
- library built for this series (`build/xray-lib.sh`): `Xray-core v26.11.9`, Go 1.27.4, NDK
  28.2.13676358 — see the `lib_sha256` in the report; `build/libxray/main.go` and
  `jni_bridge.c` are not in this repository, so patches 09 and 12 describe their changes and
  the rebuilt digest is what proves which library an APK carries.
- checks: `flutter pub get`, `flutter analyze lib/` → 0 errors, `bash -n build.sh` → ok,
  `:common/:service/:app:compileReleaseKotlin` → BUILD SUCCESSFUL
- device: vivo V2454DA (10AF4N1G8H0023C), arm64 APK only; the simple portal starts the core in
  process, `ps -A | grep -i clash` is empty, and the egress IP is the node's. Evidence lines
  are in the report for this series, not reproduced here.

Patches 03 and 04 both edit `XrayPlugin.kt` and 04 edits code 03 introduces, so 04 applies on
top of 03 only; `08..13` each edit `XrayPlugin.kt` and 09/12 edit code 08/09 introduce, so they
apply in order; 14 and 15 each apply on their own line of `portal_controls.dart` and also in
order.

**Switch timings, measured on the Motorola** (`ZY22BFXN4N`, arm64 APK `d81caaa1…`, installed over
the 20d build with `install -r`: `lastUpdateTime` 03:36:17 → 04:00:59, subscription kept).
Six consecutive switches, three each way, from `portal-transitions.log` — click → `phase=Active`
and click → rows on screen, both in ms:

| # | direction | `phase=active` | `phase=list` | rows source |
|---|---|---|---|---|
| 1 | portal → network | 622 | 150 | live, 28 |
| 2 | network → portal | 256 | 122 | live, 28 |
| 3 | portal → network | 348 | 136 | live, 28 |
| 4 | network → portal | 277 | 143 | live, 28 |
| 5 | portal → network | 375 | 135 | live, 28 |
| 6 | network → portal | 250 | 124 | live, 28 |

Before 21/21b the same tap took ~15 s: the hand-over was always ~235 ms, and the wait was the
apply debouncer plus `_awaitMode`'s 12 s deadline. A screenshot 450 ms after a tap shows the
`Авто-выбор`/`Эстония`/`Финляндия` rows with their pings; another at 651 ms shows the engine's
`VPN - Main` group strip. One owner per generation throughout (no generation carries both
`Mihomo` and `Xray`), no `result=failed`, `engine=stopped child=running` with
`listeners=probed:127.0.0.1:10810` and `egress=185.155.222.5` in the portal, `engine=running`
`child=stopped` on `:7890` in the network mode, no `[Fatal]` in `xray.log`, no
`config is not applied` and no `portal switch unconfirmed` in logcat across 14 switches.
