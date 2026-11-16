# Portal research recommendations

## Summary

The immediate priority is a native Xray `MeasureNodes` API with a *separate* core-instance slot.  It is the only listed latency mechanism that can produce an all-node Xray startup result without taking down the active simple portal.  Do not try to make the existing SOCKS sweep coexist by merely removing its Kotlin guard: `XrayStart` deliberately stops the current core first.  Keep the existing mihomo fan-out; it is already core-side probing with cancellation, batching, and throttled UI delivery.

| # | Mechanism | Verdict | Effort | Two-core lifecycle / current-UI risk |
|---|---|---|---|---|
| 1 | Native throwaway `MeasureNodes` | **ADOPT NOW** | L | High until isolated; no chip/layout/card change required |
| 2 | Live Xray observatory status | **ADOPT LATER** | L | Must retain every outbound in the live document; no UI change required |
| 3 | 4 workers, callbacks, 120 s cap | **ADOPT NOW** | M | Low once item 1 owns cancellation; no UI change |
| 4 | Loopback + inbound credentials | **ADOPT NOW** | M | Low after native tests; no UI change |
| 5 | `stats:{}` and DNS-direct bypass | **ADOPT NOW** | M | Medium config-compatibility risk; no UI change |
| 6 | Subscription body sniff ladder | **ADOPT LATER** | M | Parser-only; no UI change |
| 7 | Verbatim full-config storage + flag | **ADOPT LATER** | L | Must preserve profile/start contract; no UI change |
| 8 | `failingSince`, give up after 3 days | **SKIP** | S | Would leave unusable modes selectable for days |
| 9 | Metadata lines in subscription body | **ADOPT LATER** | M | Header-precedence/storage migration; no layout change |
| 10 | Expiry banner from `sub-expire` / `sub-info` | **ADOPT LATER** | M | Existing expiry notices can be reused; a new dashboard banner is prohibited |
| 11 | Per-row tri-state delay chip | **SKIP** | M | Explicitly changes Mark's protected chips/server card |
| 12 | Test filtered rows + 300 ms rendering throttle | **ADOPT NOW** | S | Already mostly present; no visual redesign |
| 13 | Pin selected row during re-sort | **ADOPT LATER** | M | Scroll/selection race risk; no layout change |
| 14 | Per-subscription ping settings | **ADOPT LATER** | M | Profile migration/settings scope; do not alter cards |
| 15 | Show `/proxies` latency history | **SKIP** | M | Current core already consumes history as deltas; a history UI is out of scope |
| 16 | Make Xray a `CoreInterface` implementation | **SKIP** | L | False lifecycle abstraction; use a narrow latency adapter instead |
| 17 | Core choice per profile/node | **SKIP** | L | Broad routing/config semantics, not a latency fix |

The UI constraint is treated as hard: none of the **ADOPT NOW** work changes the chips, dashboard layout, or server card.

## Per-item recommendations

### 1. `MeasureNodes(document, targets, url, timeout)` — **ADOPT NOW** (L)

Replace the SOCKS-port construction in `lib/core/xray_measure.dart` and the start/stop choreography in `_testDelayWithChild` in `lib/views/dashboard/portal_controls.dart` with a native batch call that creates a throwaway Xray instance containing only the requested outbounds, forces each outbound with `session.SetForcedOutboundTagToContext`, and calls `core.Dial`/the HTTP probe.  Return indexed results or stream them through the method channel; do not create inbounds or Dart SOCKS clients.  The current implementation has two independent failure sources: `measureConfig()` creates local listeners and `measureNode()` implements SOCKS itself, while `XrayPlugin.startMeasure()` is refused when `coreRunning` is true.  A 16–32 bounded native worker pool is appropriate; validate result values before writing `TcpDelayNotifier`.  Lifecycle risk is high until the native instance is isolated (answer A); after that the measurement slot must be stopped on cancellation/detach without touching the tunnel slot.  UI risk is none: retain `tcpDelayProvider` and the current row data source.

### 2. `ObservatoryService.GetOutboundStatus` on the running core — **ADOPT LATER** (L)

The symbols in `libxray.so` only show the module is linked; they do not make a running portal observable.  `XrayPlugin.start()` passes one selected server document through `tunDocument()`, so the live core normally does not contain all subscription nodes to report on.  To use `GetOutboundStatus`, preserve all outbounds/tags in the live document, enable `observatory`/`burstObservatory`, expose an authenticated loopback API client from `XrayPlugin.kt`, and map tags back to `XrayServerConfig` in `portal_controls.dart`.  This is valuable for the active core and ongoing health, but it is an architecture change and not a replacement for item 1's startup all-node batch.  Lifecycle risk is medium/high: API/listener ownership and a changed selected-node document must not let the observatory keep stale cores alive.  UI risk is none if it only updates the existing delay map.

### 3. Incy sweep shape (4 workers, isolation, per-result callback, 120 s timeout) — **ADOPT NOW** (M)

Apply this scheduler to item 1, not to the present port sweep.  Add a generation/cancellation token to the Dart bridge beside `TcpDelayNotifier._generation`, make the native batch return or callback each completed indexed result, cap the complete launch sweep at 120 seconds, and stop the measure slot in `finally`.  `ProxiesAction` already demonstrates the desired delivery discipline: `_DelayTestJob`, `TaskPool`, and `_scheduleDelayFlush()` in `lib/providers/actions/proxies.dart` stream results and coalesce rendering.  Four workers are a conservative default for expensive full-proxy probes; make the native concurrency configurable internally only after device measurements.  Lifecycle risk is low once item 1 has distinct slots; UI risk is none because callbacks feed the existing notifier.

### 4. Force subscription inbounds to loopback and add SOCKS/HTTP credentials — **ADOPT NOW** (M)

Harden the runtime patch in `XrayPlugin.tunDocument()`.  It currently removes only `protocol == "socks"`; provider-supplied `mixed` and `http` listeners survive, and a listening address/authentication is otherwise panel-controlled.  For every retained proxy-style inbound, force `listen` to `127.0.0.1`, disable unauthenticated UDP where it cannot be authenticated, and inject per-start random SOCKS/HTTP credentials if an inbound remains usable.  If the simple portal never needs those listeners, the safer minimal policy is to remove all provider proxy inbounds and retain only the injected TUN inbound; document that choice and test both config families.  Lifecycle risk is low but a bad JSON patch can reject an otherwise valid panel config, so add Kotlin unit fixtures and device tests.  UI risk is zero.

### 5. Inject `stats:{}` and direct DNS rules — **ADOPT NOW** (M)

Add a narrowly gated runtime patch next to `hijackTunnelDns()` in `XrayPlugin.kt`: when an `observatory`/`burstObservatory` configuration (and relevant balancer routing) is present, add an empty `stats` object if missing, resolve literal DNS-server IPs from `dns.servers`, ensure a `freedom`/`direct` outbound exists, and prepend direct rules for those IPs.  Keep the existing first TUN-port-53 rule; it solves a different problem.  This makes supplied observatory/balancer documents viable now and is prerequisite hygiene for item 2.  Lifecycle risk is medium because DNS shapes include strings and objects and rules must be idempotent; test no-DNS, hostname DNS, IP DNS, existing direct outbound, and a restart.  It does not require a visual change.

### 6. Plain/base64/url-safe/stripped body sniffing — **ADOPT LATER** (M)

`parseXraySubscriptionResult()` in `lib/core/xray_subscription.dart` currently trims then immediately `jsonDecode`s; it cannot benefit from decoding a link list because Portal has no demonstrated Xray-link-to-full-config normalizer on this path.  Implement the control-character-checked ladder only together with a supported link/config normalizer and tests for plain JSON, malformed base64, URL-safe padding, and garbage text.  On its own this would simply turn one unsupported body into another unsupported body and makes diagnostics less honest.  Lifecycle risk is none; UI risk is none.

### 7. Store full panel JSON verbatim; patch only at start with `isFullConfig` — **ADOPT LATER** (L)

`XrayServerConfig.config` is presently a decoded `Map`, and `tunDocument()` reparses/re-serializes it, so exact provider documents are not an explicit storage contract.  Introduce an opaque per-entry full-config payload and an `isFullConfig` field through the subscription model, profile persistence, `PortalRuntime.childConfigBuilder`, `PortalRuntimePlugin`, and `XrayPlugin`; create a mutable runtime copy only in Kotlin for logging, inbound hardening, stats, and DNS fixes.  The flag should select the safe full-config branch (including any future geo/matcher-cache policy), not allow providers to bypass Android-required TUN and security patches.  Lifecycle risk is high if migration loses selected-node identity or mutates persisted source; UI risk is none because the existing server card continues to receive name/description/protocol projections.

### 8. `failingSince` and three-day give-up — **SKIP** (S)

Do not replace the in-memory three-strike availability gate in `lib/core/portal_feed.dart`.  `PortalFeeds.note()` is deliberately tied to actual fetch/parse outcomes and `portalAvailabilityProvider` in `portal_controls.dart` stops offering a mode after three consecutive failures.  Waiting three days would leave a known-broken portal switch enabled, contradicting the current truthful disabled-state behavior; it also makes retries after a bad launch ambiguous.  Lifecycle risk is user-facing false starts for both cores; UI risk is a misleading switch, even without a layout change.

### 9. Body metadata lines and `profile-title: base64:` — **ADOPT LATER** (M)

The HTTP-header half already exists: `ProviderHeaders.title` in `lib/models/provider_headers.dart` decodes `base64:`, and `Profile._updateFrom()` saves recognized response headers.  Add a small, bounded metadata pre-parser before `parseXraySubscriptionResult()` that accepts only initial `#`/`// key: value` lines, then merge recognized values into `providerHeaders` with response headers winning.  Extend `providerHeaderNames` in `lib/models/profile.dart` only for supported keys and do not log decoded secrets.  Lifecycle risk is none; UI risk is none because this enriches existing profile/announcement surfaces rather than the protected server card.

### 10. `sub-expire` / `sub-info` expiry banner at <=3 days — **ADOPT LATER** (M)

Portal already parses `subscription-userinfo` into `SubscriptionInfo`, displays expiry facts, and has one-per-threshold notices in `ProfilesAction.noticeSubscriptionExpiry()` (`lib/models/profile.dart`, `lib/providers/actions/profiles.dart`).  Map a validated `sub-expire` value into that existing expiry source and reuse its three-day schedule first; define a separate, dismissible profile-level presentation for `sub-info` only after Mark approves its surface.  Do not add a dashboard banner or alter the dashboard layout to satisfy this item.  Lifecycle risk is none; UI risk is medium only if the generic provider copy is allowed to become a new dashboard element.

### 11. Bolt → queued clock → spinner → milliseconds on each row — **SKIP** (M)

`ProxiesAction` already tracks acquired/started/finished keys through `pendingDelayTestsProvider`, and it batches state changes every `renderThrottleDuration`; the dashboard also already has a group-level spinner.  Rendering those states as a new tri-state delay chip in `_PortalNodeRow`/the server card in `portal_controls.dart` is exactly the protected chip/server-card change Mark prohibited.  Lifecycle risk is low, but UI risk is disallowed; retain state for existing controls and logs only.

### 12. Test only currently filtered rows and throttle render updates — **ADOPT NOW** (S)

Keep and reuse what is already implemented.  `ProxiesAction.delayTestPageGroup()` filters `group.all` with `SearchQuery` before calling `delayTest`, and `_scheduleDelayFlush()` uses the shared `renderThrottleDuration`, currently 300 ms in `lib/common/constant.dart`.  Ensure any explicit “test visible” entry point calls this method; startup testing remains intentionally all-node, as requested, rather than inheriting a transient user filter.  Lifecycle risk is low because `cancelDelayTests()` already clears pending work on core disconnect; UI risk is none.

### 13. Keep the selected row stable during delay sort — **ADOPT LATER** (M)

`PortalSelectionNotifier` already preserves a selected name across list reordering, and the sort in `PortalServerList` derives ranks from `tcpDelayProvider`/`delayProvider`; identity is better than position.  Add a stable key plus a scroll-anchor/keep-visible policy only after item 1 provides streaming all-row results, and avoid changing the list/card structure.  It must coordinate with `PortalPendingNotifier` so a delayed selection acknowledgement cannot pin an obsolete row after a profile update.  Lifecycle risk is low; UI risk is medium (scroll jumps) but can be eliminated without a layout change.

### 14. Per-subscription ping protocol, URL, display, and sort settings — **ADOPT LATER** (M)

The current URL is global (`appSettingProvider.testUrl`) while `Group.testUrl` can override engine checks; sort is already separately persisted per portal mode in `PortalSortNotifier`.  Add profile-scoped probe preferences only after item 1 defines supported native probe modes and result semantics, then route the chosen URL through `_testDelayWithChild`/`MeasureNodes` and retain the existing mode sort.  Do not add display-format controls to the protected row/chip; a settings-only implementation is the acceptable scope.  Lifecycle risk is low; UI risk is contained to a future settings surface.

### 15. Latency history from `/proxies` `history[]` — **SKIP** (M)

The repository already takes the useful part of this mechanism without exposing history to the UI: `core/delay_watch.go` reads `ExtraDelayHistories()`, emits only new last records as delay events, and `core/proxy.go` deliberately removes `history` from the proxy view (enforced by `core/hub_test.go`).  A history chart/store adds retention, profile scoping, and stale-value policy without solving startup Xray measurement.  Lifecycle risk is low but memory/state risk is real; UI risk would require a new presentation, so keep the current delta path.

### 16. Put Xray behind the same broad `CoreInterface` — **SKIP** (L)

`CoreInterface` in `lib/core/interface.dart` owns a large mihomo lifecycle and management contract—config apply, groups, listeners, providers, routes, connections—not just `asyncTestDelay`.  Xray's TUN child is instead coordinated by `PortalRuntime`/`PortalRuntimeCoordinator`, and pretending it implements the same lifecycle would obscure the single-tunnel-owner invariant.  If reuse is wanted after item 1, introduce a narrow `LatencyProbe` interface used by `ProxiesAction` and `TcpDelayNotifier`, not a fake `CoreInterface` implementation.  Lifecycle risk of the proposed abstraction is high; UI risk is none but the resulting bugs would surface in it.

### 17. Core choice per profile/node and config-type default — **SKIP** (L)

Portal currently has a deliberately separated mode model: mihomo owns rule groups and Xray owns parsed full-config nodes (`portal_controls.dart`, `xray_subscription.dart`), with distinct persisted picks.  A per-node engine choice needs capability detection, conversion guarantees, migration of selections, tunnel handoff rules, and an explanation when a node only one core supports; it is unrelated to repairing startup latency.  Lifecycle risk is very high because a switch could replace the active TUN owner; UI risk is also high because it requires an engine-choice affordance that changes the current card/list semantics.

## A. Can a measurement instance run with the tunnel child core in this process?

**Not with the current library or bridge.**  `XrayPlugin.startMeasure()` rejects `coreRunning`, but removing that guard would be destructive: `XrayStart()` in `~/.hermes/cache/scratch/xraylib/build/libxray/main.go` takes `coreMutex`, calls `stopLocked()`, and stores every successful run in one global `coreInstance`.  Calling it with `tunFd = -1` for the measurement therefore stops the TUN child before it starts the measuring instance.  Conversely, a later child restart stops the measurement.  The Dart comments in `PortalRuntime.startMeasure()` and `_testDelayWithChild()` correctly describe this current one-at-a-time behavior, including the intentional `setup.setRunning(false)`/restore.

The smallest correct change is a distinct native measurement slot, not a second call to `XrayStart`.  Add `measureInstance *core.Instance` plus explicit exported `XrayMeasureNodes(...)` and `XrayMeasureStop()` functions in `main.go`; retain `coreInstance` and `XrayStop()` exclusively for the TUN child.  `XrayMeasureNodes` should start its own no-inbound document, run the forced-outbound probes, return/stream indexed results, close **only** `measureInstance`, and never alter `xray.tun.fd`.  Protect the two slots with a clear lock policy (one mutex is simplest for start/stop state; do not hold it across the full probe batch if that would block stopping the child).  Add matching JNI methods and a dedicated `measureRunning` state in `XrayPlugin.kt`; route `PortalRuntimePlugin`/`PortalRuntime` to that API and delete `measureConfig`’s listeners plus the Dart SOCKS client when it is proven.

Before shipping, verify on a physical Android device: (1) start a TUN child and carry traffic; (2) start a 16/32-node measure batch and verify traffic never drops, `PortalRuntimeStatus` generation/owner/fd epoch do not move, and all results map to their original nodes; (3) cancel the batch, switch Xray nodes, close/revoke VPN, rotate the TUN fd, and detach Flutter while a probe is in flight; (4) verify each path closes only its own instance, no TCP listener/port remains, and no goroutine/native leak accumulates across repeated batches; and (5) exercise freedom, blackhole, bad tag, DNS, TLS, and slow/dead-node fixtures.  Concurrent `core.StartInstance` support is an implementation assumption to prove under these tests, not a property the current wrapper establishes.

## B. Should mihomo startup probing move to its group health check?

**No material gain; keep the Dart-dispatched, core-executed `asyncTestDelay` fan-out.**  `ProxiesAction._runDelayTests()` calls `CoreController.getDelay()` and `CoreInterface.asyncTestDelay()`, which reaches `handleTestDelay()` in `core/delay.go`; the actual network check is already mihomo’s `proxy.URLTest`, not a Dart socket probe.  It is bounded twice (`TaskPool(maxConcurrentDelayTests)` in Dart and `delayTestSlots` in Go), uses the caller’s URL/timeout, deduplicates targets by URL/name, and writes results through the existing 300 ms buffered flush.  `portal-0.01a`'s remembered behavior was this style of engine delay testing against a running core, not a separate universal app pinger.

The engine’s own URL-test/group health activity is useful as background health and is already harvested by `core/delay_watch.go` from `ExtraDelayHistories()`, but it is not a reliable one-shot “every row has a launch result” operation: it follows group/provider policy and timing, may use a different URL, and does not promise all nodes.  Replacing the fan-out would also break the cancellation contract: `_delayTestJobs` could no longer mark queued tasks cancelled, `silentCoreAfter` could not stop a batch whose group checks keep running, and `TaskPool` would no longer impose UI-request fairness or the established pending/started/finished transitions.  Late engine history events would arrive after `cancelDelayTests()` and need a new generation filter.  Keep the current pipeline for explicit/startup tests; let `delayWatcher` enrich it opportunistically, rather than making it the scheduler.
