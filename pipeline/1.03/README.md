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
- checks on that tree: `flutter pub get`, `flutter analyze lib/` → 0 errors (12 pre-existing
  info/warning issues, none in a patched file), `bash -n build.sh` → ok

Patches 03 and 04 both edit `XrayPlugin.kt` and 04 edits code 03 introduces, so 04 applies on
top of 03 only; 03, 05 and the earlier pair apply on their own. Nothing here was run on a
device: the JNI entry points do not exist until the sibling task's `libxray.so` is built.
