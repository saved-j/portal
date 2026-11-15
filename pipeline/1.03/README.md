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
