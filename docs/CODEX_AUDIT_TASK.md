# Task: full audit of the Portal Android app before a release

Audit the repository at `/Users/saved/.work/portal` (Flutter + Kotlin, a fork of FlClashX) and
report findings. You may read any file and run read-only commands (`git log`, `git diff`,
`flutter analyze`, `grep`, `./gradlew tasks`). Do NOT modify any file, do NOT install anything,
do NOT push, do NOT create tags.

## What the app is

Two cores, two modes, one tunnel at a time:

* **Network of portals** — mihomo (`lib/core/*`, the engine), rule-based groups, its own delay
  API.
* **Simple portal** — Xray loaded in-process as `libxray.so` (`android/app/src/main/jniLibs/arm64-v8a/libxray.so`),
  started with a tun fd handed over by `VpnService`; our own cgo wrapper exports
  `XrayStart/XrayStop/XrayVersion/XrayMeasure/XrayMeasureStop`.
* `PortalRuntime` (`lib/core/portal_runtime.dart` + `PortalRuntimeCoordinator` in Kotlin) is the
  single owner of the tunnel, with generations and an fd epoch.
* Latency: `_testDelayWithChild` / `_testDelayWithEngine` in
  `lib/views/dashboard/portal_controls.dart`. Xray nodes are measured in a **separate** core
  instance (`measureMutex`/`measureInstance` in the native wrapper) so a sweep runs beside the
  portal; mihomo nodes are measured by raising the engine for the sweep and stopping it after.
  A measurement is reused for two minutes (`_delayFreshness`); a mode switch cancels a sweep.
* Two caches, one per core: `portalEngineRowsProvider`, `portalChildRowsProvider`.

## Recent history you must read before judging

`git log --oneline -15` — patches 38–44 are this week's work (native measure slot, waves,
inbound hardening, stats/DNS-direct, launch sweep for both lists, 2-minute freshness).
Read the diffs of those commits; the audit is of the state they produced.

## Audit scope — answer each with evidence (file:line, quoted code where it matters)

1. **Correctness of the measurement path.** Can two sweeps interleave? Can a cancelled sweep
   still write rows? Is `runningSweep`/`_generation`/`measuredAt` coherent under
   (a) mode switch mid-sweep, (b) profile switch, (c) portal opened/closed mid-sweep, (d) VPN
   revoked, (e) app backgrounded? Does `stopMeasure` ever kill the tunnel's core?
2. **Native wrapper.** `~/.hermes/cache/scratch/xraylib/build/libxray/{main.go,measure.go,jni_bridge.c}`.
   Lock ordering, instance lifetime, goroutine leaks, JNI string handling, the `limit`/`timeout`
   bounds, what happens if `XrayMeasure` is called concurrently with `XrayStop`.
3. **Tunnel lifecycle.** `PortalRuntime`, `ServiceController`, `VpnService.kt`: any path that
   leaves two owners, a leaked fd, a never-closed instance, or a state that says Active while
   nothing reads the tunnel.
4. **Security.** Inbound hardening (`XrayPlugin.tunDocument`), provider-supplied documents,
   what a malicious subscription could still make the app do, log files that may contain
   secrets, the subscription URL in logs.
5. **Resource use.** Anything that measures/loops/polls without a bound, wake-locks, CPU in
   idle, why a 24-node sweep takes 28 s at 4 workers (is the chunking costing more than it
   saves?).
6. **UI/state consistency.** Does the list ever show rows from the other core? Is the selected
   row stable across re-sorts and sweeps? Do the chips, dashboard layout and server card match
   what the owner froze (chips must not change)?
7. **Release readiness.** Version plumbing (`pubspec.yaml`, `android/local.properties`,
   `build.gradle.kts` reading `PORTAL_VERSION_NAME`), signing, `flutter analyze` warnings
   (not only errors), any TODO/FIXME/hardcoded string that should be localized, leftover dead
   code from removed features (socks sweep, XRAY-SOCKS group, the old bridge).

## Output

Write `/Users/saved/.work/portal/docs/AUDIT_2026-11-16.md` with:

* a table: severity (BLOCKER / MAJOR / MINOR / NIT) × area × one-line finding;
* per-finding detail: evidence, why it matters, suggested fix, effort S/M/L;
* a straight answer to "is this shippable as a test build for the owner", listing exactly what
  must be fixed first and what can wait;
* anything you consider a real risk that this brief did not ask about.

Be specific and skeptical: a finding without a file:line is not a finding. If something is fine,
say so briefly instead of padding.
