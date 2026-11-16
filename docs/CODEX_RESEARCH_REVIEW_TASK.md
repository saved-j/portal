# Task: review a list of stealable mechanisms and say what to adopt

You are reviewing a research backlog for an Android proxy client (Flutter + Kotlin, a fork of
FlClashX). Two cores: mihomo ("network of portals") and Xray loaded in-process as a c-shared
library `libxray.so` ("simple portal", started with a tun fd handed over by VpnService, exports
`XrayStart(config, tunFd, assetDir)`, `XrayStop()`, `XrayVersion()`).

Repository: /Users/saved/.work/portal (read it, do not modify it).

## Current state of latency testing

* mihomo mode: engine's own per-node delay via `ProxiesAction.delayTest` -> core
  `asyncTestDelay` -> mihomo API. Works, `maxConcurrentDelayTests = 32`.
* Simple portal (Xray): we invented a sweep that starts a SECOND core instance with 24 socks
  inbounds (`lib/core/xray_measure.dart`, `XrayPlugin.startMeasure`) and a hand-written Dart
  socks client. It does not work (measured=0). Mark calls it a hack and wants the mechanism
  copied from proven clients.
* Mark remembers that in an earlier build (tag `portal-0.01a`, see `git show portal-0.01a:...`)
  "the app pinged every server by itself at startup". Reality: that was mihomo's own group
  delay test against an already-running core. He wants that behaviour back for BOTH cores,
  including "allow both cores to run at once, just for pinging", so the app gets numbers for
  Xray and mihomo servers right after launch.

## What to do

Read the repo (especially `lib/views/dashboard/portal_controls.dart`,
`lib/core/portal_runtime.dart`, `lib/core/xray_measure.dart`,
`android/app/src/main/kotlin/com/follow/clashx/plugins/XrayPlugin.kt`,
`android/app/src/main/kotlin/com/follow/clashx/plugins/PortalRuntimePlugin.kt`,
`lib/providers/actions/proxies.dart`, `lib/core/interface.dart`) and then judge the list below.

For EACH item give: verdict (ADOPT NOW / ADOPT LATER / SKIP), one-paragraph reasoning that
names the actual files and functions it would touch, estimated effort (S/M/L), and the risk to
the two-core lifecycle and to the current UI (Mark forbids changing the chips, the dashboard
layout, and the server card).

The list (all verified against upstream sources; details in
/Users/saved/.work/portal/docs/research/INCY-CLIENT-RESEARCH.md and
/Users/saved/.work/portal/docs/RESEARCH_happ_incy.md):

1. `MeasureNodes(document, targets, url, timeout)`: one throwaway instance whose document has
   only `outbounds`, each node timed with `session.SetForcedOutboundTagToContext` +
   `core.Dial`, 16-32 concurrent, no inbounds, no ports. Already compiled and executed against
   our exact core commit (freedom tag 1138 ms, blackhole failure, unknown tag -> core error).
   Same shape as `XTLS/libXray` `PingBatch` and `AndroidLibXrayLite.MeasureOutboundDelay`.
2. `ObservatoryService.GetOutboundStatus` on the ALREADY RUNNING core (what Happ/Incy appear to
   read). `app/observatory` is already linked into our `libxray.so` (strings present).
3. Incy's sweep shape: parallelism 4, worker isolation, per-result callback, 120 s global
   timeout.
4. Security: force every subscription-declared inbound to bind `127.0.0.1` and inject SOCKS/HTTP
   credentials (Happ does this) so a panel cannot turn the client into an open relay.
5. Inject `stats:{}` and a `direct` routing rule for DNS server IPs (breaks the
   observatory<->DNS loop, Happ).
6. Subscription format sniff ladder: plain base64 -> url-safe base64 -> strip non-base64 and
   decode, with a control-character check on the result (Incy).
7. Store the panel's JSON verbatim and patch only at start, gated by an `isFullConfig` flag that
   crosses Flutter->native (Happ).
8. `failingSince` + `giveUpAfter(3 days)` instead of counting three strikes (Hiddify).
9. Headers inside the subscription body (first lines `#`/`//` as `key: value`) and
   `profile-title: base64:<value>` (Hiddify).
10. Subscription expiry banner from `sub-expire`/`sub-info`, warning at <= 3 days (Happ).
11. Tri-state delay chip on each row: bolt -> clock (queued) -> spinner -> "123 ms" (FlClash).
12. "Test only the rows currently filtered" plus a 300 ms render throttle (FlClash).
13. Pin the selected row while a re-sort happens (Hiddify).
14. Per-subscription ping settings: protocol, test URL, display format (ms / bars / both /
    dots), sort order (Incy).
15. Latency history from the engine's own `/proxies` `history[]` (ClashX.Meta).
16. Put Xray behind the same `CoreInterface` that mihomo uses (`asyncTestDelay(url, proxyName,
    timeout)`), so the proxies UI cannot tell the cores apart.
17. Core choice per profile/node with a per-config-type default (v2rayN).

## Two specific questions to answer with reasoning

A. Can the measurement instance (item 1) run WHILE the tunnel's own child core is running in
   the same process, so the app can ping Xray nodes at startup without closing the portal? Look
   at `XrayPlugin.start()`/`startMeasure()` and the single-instance assumption in
   `~/.hermes/cache/scratch/xraylib/build/libxray/main.go` (XrayStart is idempotent and stops
   the previous instance). If it cannot, propose the smallest correct change (e.g. a second
   instance slot, `XrayMeasureNodes` that keeps its own instance separate from `coreInstance`)
   and say what must be verified on a device.

B. For mihomo, is there anything to gain from moving the startup ping from Dart-side
   `delayTest` fan-out to the engine's own group health check, and what would break in our
   cancelled/debounced pipeline (`_delayTestJobs`, `silentCoreAfter`, `TaskPool`)?

Write the answer as a markdown report to
/Users/saved/.work/portal/docs/CODEX_RECOMMENDATIONS.md with a summary table first, then the
per-item verdicts, then the two answers. Do not modify any other file.
