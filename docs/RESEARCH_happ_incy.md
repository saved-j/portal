# Happ / Incy: proven mechanisms worth copying

Research date: 2026-11-16. Target: Portal (FlClashX fork, mihomo + in-process Xray via libxray `XrayStart`/tun fd).

Method: official developer docs (both vendors publish them), the public wrapper repos
(`HappDev/libXray`, `Flyfrog-LLC/libXray`, `Flyfrog-LLC/hev-socks5-tunnel`), and **symbol-level
analysis of the shipped binaries** (`nm -D` on `libgojni.so`, strings on `classes*.dex`).
Nothing below is inferred from screenshots. Items I could not confirm are marked UNVERIFIED.

Local artifacts (throwaway, under scratch):
`/Users/saved/.hermes/cache/scratch/{happ_su,libXray,flibx,hprof,incy,Happ.apk,hapk,Incy.apk,apk}`

---

## 1. Which core, and how "simple" vs "tunnel" maps to it

**Happ — Android** (`Happ.apk`, 69 MB, package `su.happ.proxyutility`):

| native lib | role |
|---|---|
| `libgojni.so` (37 MB) | gomobile-bound Xray fork + WireGuard (`Libwg`) + process finder. Packages: `github.com/xtls/xray-core`, `xtls/reality`, `refraction-networking/utls`, `vishvananda/netlink`, `flyfrog-llc/android_wrapper_build` |
| `libhev-socks5-tunnel.so` | `hev-socks5-tunnel` — TUN fd → SOCKS5 (C) |
| `libzstd-jni` | zstd-packed assets (geo files ship compressed) |
| `libtoolChecker.so` | rooted/emulator detection |
| `libcore.so` | `AntiFilterHandle` — socket-level DPI helper with `protectSocket(fd)` |
| `libmmkv.so` | settings/profile store |

Java side: `Lsu/happ/tunnel/TProxyService;` (JNI wrapper around hev), `XRayConfig` Gson DTOs
(`$Meta`, `$Api`, `$BurstObservatoryObject$PingConfigObject`, `$ObservatoryObject`),
enums `EConfigType`, `ECoreType`, `EPingType`, `GoPingType`, `EDnsType`, `InboundAuthMode`,
`SubscriptionSortType`, `EAutoSwitchType`.

**Happ — desktop** (from `third-party-libraries.md`): Xray-core 25.10.15 + **sing-box 1.12.12** +
**tun2proxy 0.7.15** + byedpi + Mullvad win-split-tunnel.

**Incy — Android** (`Incy.apk`): one `libgojni.so` that is a **Go + Rust hybrid**. Rust side is an
Xray-compatible core (`xray_netstack`, `xray_tun`, `xray_proto`, `xray_api`, `smoltcp`, tokio), Go
side keeps `gvisor` netstack ("Using gVisor TUN"), an in-process tun2socks, `wireguard-go`
(AmneziaWG), SSTP and AnyConnect (`openConnect*`). Play changelog for 3.9.9 says "Moving to
Rust-core". Exported Java-incycore API (abridged, verbatim):

```
startXray, startXrayWithTunFd, xrayStart, xrayStop, isXrayRunning
startVPN, stopVPN, tun2SocksStart/Stop/GetStats/IsRunning
ping, pingConfig, pingConfigs, pingConfigsBatchSync, pingProxy, pingXray, measureDelay
registerDialerController, proxyDialerController.protectFd, proxyPingCallback.onPingResult/onPingComplete
initDns, resetDns, cutGeoData, analyzeGeoIP, analyzeGeoSite, validateGeoFiles, loadGeoStatsCache
initMemoryManagement, memorySetGCPercent/Limit/MaxProcs, freeMemory
amneziaWGStart/Stop/Stats, sstpStart, openConnectStart
```

**Mode mapping (both vendors, same shape):**

| mode | what runs | tunnel |
|---|---|---|
| proxy / "simple" | Xray with a **loopback SOCKS/HTTP inbound only** (`127.0.0.1:10808`, HTTP `10809`) | none; the OS proxy points at it, or the app dials it directly |
| tunnel | same Xray config, plus one of: `startXrayWithTunFd` (core owns the fd) **or** hev-tun2socks holding the fd and forwarding to `127.0.0.1:10808` | `VpnService` → fd |

Happ exposes the switch as subscription params: `tun-type: [singbox, tun2proxy, default, xray]`,
`tun-mode: [system, gvisor]`, `custom-tunnel-config` ("for the sing-box core"), `proxy-enable` /
`tun-enable`.

**Fit for Portal:** identical to our `simple portal`. Two things we do not have: (a) the desktop
core-choice matrix — the TUN engine is a *strategy*, not the core; (b) a documented `tun-type`
style setting so a provider can force gVisor when the kernel stack misbehaves (Docker/iptables
conflicts on macOS are named as the reason).

---

## 2. Latency for ALL servers

Happ ships **three** measurement paths, all inside the native core, selected by an enum:

- `GoPingType` / `EPingType` in Kotlin, values seen: `TCP`, `ICMP`, `PROXY_GET`, `PROXY` (HEAD).
- Exported natives: `libxray_Libxray_measureOutboundDelay`, `..._measureOutboundDelayWithType`,
  `libxray_XRayPoint_measureDelay` (+`WithType`), and the same pair again for WireGuard
  (`libwg_Libwg_measureDelay`, `...WithType`).
- Separately, `XRayPoint.queryStats`, `queryStatsServer`, `queryStatsCustom`, `queryStatsSys` —
  the stats gRPC is queried per outbound/inbound tag.

Doc semantics (`dev-docs/ping.md`, verbatim):
> "**TCP Ping** — Measures latency by sending a TCP packet directly to the server. Does not require
> disabling the tunnel. However, when a CDN is used, it may not reflect the real latency …
> **via Proxy Ping** — Runs through the active VPN connection and includes the full path … including
> TLS handshake."

Sequence for via-proxy is spelled out: resolve node domain → TCP → TLS handshake → *(server side)*
resolve test target → TLS to target → measure response. Default check URL:
`https://cp.cloudflare.com/generate_204` (`check-url-via-proxy`).

Bulk behaviour: `Settings → Subscriptions → Ping on Launch` pings **every** server on every launch;
`ping-result: [time, icon]` switches the whole list to a green-check / red-bang icon; `sort-order`
and `subscription-autoconnect-type: [lastused|lowestdelay|random]` consume the results.

Incy adds an explicit batch entry point (`pingConfigsBatchSync`) plus a **result callback from
native** (`proxyPingCallback.onPingResult` / `onPingComplete`), i.e. the core streams per-node
latency instead of the UI polling N futures.

**What is confirmed vs not:** the API surface is confirmed by symbols; whether Happ measures each
node through *one* core instance with N outbounds, or spins a temporary instance per node, is
**UNVERIFIED** (Go symbols are stripped; `happ_su`'s sibling `HappDev/libXray` still carries only
the old serial `Ping()` that starts a throwaway core with one HTTP inbound). Incy's
`pingConfigsBatchSync` name and the callback shape point at one batched core run.

**The mechanism that needs no guessing — and that both clients' configs assume — is Xray's own
observatory API.** `app/observatory/command/command.proto` ships in stock Xray:

```proto
message GetOutboundStatusResponse { xray.core.app.observatory.ObservationResult status = 1; }
message OutboundStatus { bool alive=1; int64 delay=2; string last_error_reason=3;
                        string outbound_tag=4; int64 last_seen_time=5; HealthPingMeasurementResult health_ping=7; }
service ObservatoryService { rpc GetOutboundStatus(...) }
```

`HealthPingConfig` has `destination`, `connectivity`, `interval`, `samplingCount`, `timeout`,
`httpMethod`; `observatory.Config` has `enable_concurrency`. Happ's Kotlin models
`ObservatoryObject` + `BurstObservatoryObject$PingConfigObject`; Incy documents full-config patching
for `burstObservatory` and its Rust core registers
`ObservatoryService.get_outbound_status`, with the guard string
`api.services: ObservatoryService needs "observatory" or "burstObservatory"` and
`client build: API/metrics must listen on a loopback IP`.

**Fit for Portal:** we already build a throwaway "measure" document with N outbounds behind N socks
inbounds (`XrayPlugin.startMeasure`, and its comment says exactly this). That is the right fallback
but it costs a core raise per sweep. The cheap complement is: keep the *live* core's document with
all nodes as outbounds + `observatory` enabled, and read `GetOutboundStatus` over the existing API
inbound — per-node delay, alive flag and last error for the price of a gRPC call, with no teardown
and no second process. Rough edge to remember: observatory needs `dns` that does not route through
the balancer (Incy injects a `direct` rule for each `dns.servers` IP "to prevent a circular
dependency").

---

## 3. Subscription storage and formats

**Happ** (docs + `XRayConfig$Meta` in dex):

- Three body shapes: plain/base64 list of share links; **JSON array of full Xray configs**; encrypted
  `happ://crypt4/` (RSA-4096) or `crypt5`.
- JSON item shape (from a bug report reproducing Remnawave output, consistent with the docs):
  `{ "remarks": "...", "dns": {...}, "inbounds": [...], "outbounds": [...], "routing": {...}, "burstObservatory": {...} }`
  — one item = one "server" in the UI.
- Passthrough rule (`examples-of-links-and-parameters.md`, verbatim): "When the XRAY core is
  launched, this JSON configuration is passed exactly as is … standard HAPP routing rules and
  interface settings are not applied". The app keeps only: geo file selection/trimming, and DNS
  inherited from the routing profile.
- Per-node meta: `"remarks"` = name; `"meta": {"serverDescription": "..."}`
  (≤30 chars, replaces the protocol subtitle). In links: `#Title?serverDescription=<base64>`.
  One occurrence of a `server_flag` meta key exists in Happ's dex string pool — **UNVERIFIED**
  as a documented field; flags are otherwise derived from the resolved exit IP via `geoip.dat`
  (`Ping()` returns `delay:countryCode:`).
- Subscription-level metadata: `subscription-userinfo: upload=..; download=..; total=..; expire=..`
  (`expire` in seconds; Incy additionally accepts ms when `> 32000000000`), `profile-title`
  (≤25 chars, base64 allowed), `support-url`, `profile-web-page-url`, `announce`
  (`base64:` prefix, ≤200 chars), `profile-update-interval` (hours, multiple of 1).
- Clash YAML: accepted (Happ's wrapper `ConvertShareTextToXrayJson` handles "Clash yaml, Clash.Meta
  yaml" via `nodep/clash.go` → xray outbounds); Incy strips `.yaml`/`.txt` from
  `content-disposition` when deriving the profile name.

**Practical detail worth copying:** the wrapper normalises *everything* into one internal model —
`XrayJson{ outbounds: [ XrayOutbound{ name, protocol, settings, streamSettings } ] }` — with
`FlattenOutbounds()` splitting multi-server outbounds into one-outbound-per-server and keeping the
display name on the outbound (`json:"name"`). Storage is the same JSON the core eats.

**Fit for Portal:** we can adopt `meta.serverDescription` + `#Title?serverDescription=` and the
JSON-array subscription verbatim; both are already emitted by panels (Remnawave, 3x-ui) for Happ,
so supporting them costs nothing and buys immediate provider compatibility.

---

## 4. TUN fd and DNS

**Happ mobile:** `VpnService` → `hev-socks5-tunnel` → `127.0.0.1:10808` (socks) → Xray → server.
Confirmed by the shipped `libhev-socks5-tunnel.so` + `Lsu/happ/tunnel/TProxyService;`, and described
externally for the whole client family (runetfreedom, Apr 2026: "VpnService -> tun2socks -> xray
socks5 -> VPN server -> freedom"). Alternative path where the core owns the fd: `coreRunLoopWithTun`.

**Incy:** `startXrayWithTunFd` (Rust `xray_tun` + `smoltcp` netstack) *or* `startTun2Socks` (Go,
gVisor netstack: string "Using gVisor TUN"). Its patching rules for provider-supplied full configs
(`full-xray-config`) are the best-specified part of either client:

1. `log.loglevel`/`access`/`error` forced to the app's file.
2. Every non-internal `socks`/`mixed`/`http` inbound gets `listen: 127.0.0.1` forced; **ports are not
   changed** — 10808 socks, 10809 http, "these are the client's entry points". If no socks-like
   inbound exists, a `mixed` 127.0.0.1:10808 with sniffing is injected.
3. "For targeted inbounds without their own authorization, the client adds credentials so the port
   does not remain an open relay."
4. If `burstObservatory`/`observatory` present but no `stats`, inject `"stats": {}`.
5. Observability/DNS loop break: DNS server IPs from `dns.servers` are prepended as routing rules
   with outbound `direct` (freedom added if missing).
6. Full configs → skip geo trimming and `mph_cache.dat` (DomainMatcher serialisation cache is
   "incompatible with full JSON configurations"; the file is deleted), and pass `isFullConfig` to
   the iOS Network Extension via `providerConfiguration` + shared defaults.
7. DNS: if `dns.servers` non-empty, leave it alone (keep `domains`/`expectIPs`); if empty, inject
   `queryStrategy` + `hosts` "otherwise DNS queries would leak"; always narrow the `fakedns` pool to
   a small subnet.

**Hardening both vendors converged on, and the reason:** stock clients ran the loopback SOCKS inbound
with **no auth and UDP enabled**, so any local app (or spyware in a work profile — loopback is not
isolated by Knox/Shelter) could use the tunnel or enumerate the exit IP. Happ now ships
`socks-auth-mode: [auto, manual, from-json, disable]` + `socks-auth-user/password` (auto = "automatic
generation and injection of data into configs and the tunnel"), same for HTTP. Incy does the same in
`patchFullConfigInbounds`. Note the article's caveat: SOCKS UDP ignores auth, so UDP must be disabled
or proxied separately.

**Fit for Portal:** we already hand the fd to the core; keep that, but copy (a) forced
`127.0.0.1` + injected credentials on any provider-supplied inbound, (b) `stats`/`direct`-rule
injection, (c) the "full config → don't touch DNS, trimmed geo or matcher cache" branch keyed by a
boolean that crosses the Flutter→native boundary. Also copy Happ's `EDnsType` split of
remote/domestic DNS with `DnsHosts` (hosts-map for the DoH endpoint itself, so bootstrap does not
loop).

---

## 5. UI / provider tricks

- **Protocol label** = subtitle under the node name, auto-derived (`VLESS`, `VMess`, `Trojan`…),
  replaced by `serverDescription` when present. Cheap, and providers pay for it.
- **Flags** derived from the node's *resolved exit* country via `geoip.dat` (libXray `Ping()` returns
  `delay:countryCode:`; `findCountryCodeOfIp` matches the exit IP against `router.GeoIPList`).
  Incy keeps a separate icon-preset repo (`INCY-DEV/incy-icons`).
- **Expiry**: `sub-expire: 1` + `sub-expire-button-link` show a banner "Your subscription expires in
  N days" only when ≤3 days or already expired; `sub-info-*` (text/color/button) is the generic
  banner and is suppressed while an expire banner is active; sending `0` disables either.
  `notification-subs-expire` turns on one local notification per day for the last three days —
  implemented as `SubscriptionUpdater$ExpireReminderTask` alongside `SubscriptionUpdater$UpdateTask`
  and `SubscriptionUpdaterReceiver`. So: **one updater owns interval updates *and* expiry reminders**.
- **Update behaviour**: `profile-update-interval` hours (multiple of 1); if a scheduled update was
  missed it runs on next launch; `subscription-auto-update-enable` / `...-open-enable` are global
  kill-switches that let each subscription decide when off; on failure the provider can move users
  with `new-url` (full URL) or `new-domain` (host only, path preserved) and can nominate a
  `fallback-url` used when the main URL errors 300–599 **or does not answer within 9 s**.
- **Subscription UX params that cost nothing to support**: `subscriptions-collapse`,
  `subscriptions-expand-now` (push an update to unfold), `subscription-pin`,
  `hide-settings` (view/edit of node config hidden), `dont-use-filter`, `per-app-proxy-list[-invert|-set]`.
- **Incy-only, and the nicest one:** the whole config is stored **verbatim** (field `fullConfigJson`)
  and patched at start — never re-serialised from UI fields. That is why balancers, observatories and
  custom routing survive a round-trip.

---

## 6. Ordered "steal this" list

| # | mechanism | evidence | fit |
|---|---|---|---|
| 1 | Per-node delay from the live core via `observatory` + `GetOutboundStatus` (delay/alive/lastError per outbound tag) | Xray `app/observatory/command/command.proto`; Incy registers the service; Happ models `ObservatoryObject`/`BurstObservatoryObject` | replaces (or backs off) our per-sweep `startMeasure` core raise; one gRPC read, no teardown |
| 2 | Ping "type" as an enum handled in the core (`TCP` / `ICMP` / `PROXY_GET` / `PROXY_HEAD`) + a batched entry (`pingConfigsBatchSync`) with a native callback | Happ `GoPingType`, `measureOutboundDelayWithType`; Incy `proxyPingCallback.onPingResult` | one code path for list sweep, per-node check and "check current connection"; UI picks type, core does work |
| 3 | Inject SOCKS/HTTP auth into every provider-supplied inbound; force `127.0.0.1` | Happ `socks-auth-mode: auto`; Incy "adds credentials so the port does not remain an open relay"; runetfreedom writeup on the open-relay class of bug | closes the same localhost hole we inherit from libxray |
| 4 | Store provider JSON **verbatim**, patch at start (`log`, `listen`, auth, `stats`, DNS-direct rule), flag `isFullConfig` to skip geo-trim/matcher cache | Incy `full-xray-config` doc, `patchFullConfigInbounds`, `mph_cache.dat` | keeps balancers/observatory/routing intact; makes JSON subs first-class |
| 5 | Normalise all inputs to one model `{outbounds:[{name, protocol, settings, streamSettings}]}`, one outbound per server, display name on the outbound | `HappDev/libXray/nodep/xray_json.go`, `share.go` ("Clash yaml, Clash.Meta yaml"), `clash.go` | that model is literally the core's input; kills per-protocol special cases in the UI |
| 6 | JSON subscription = array of full configs with `remarks` + `meta.serverDescription`; `#Title?serverDescription=<b64>` in links | Happ dev-docs; Remnawave/3x-ui emit it for Happ UA | free provider compatibility, fixes our "protocol label" subtitle |
| 7 | Flag from exit IP via `geoip.dat` country code | `libXray/ping.go::findCountryCodeOfIp`, `Ping()` returning `delay:CC:` | flags without trusting the node name |
| 8 | `subscription-userinfo` + `sub-expire`/`sub-info` banner matrix + 3-day reminders owned by the updater | Happ app-management doc; `SubscriptionUpdater$ExpireReminderTask` | one service owns updates and reminders; providers control the copy |
| 9 | `new-url` / `new-domain` / `fallback-url` (300–599 or 9 s timeout) | Happ app-management doc | domain-blocked recovery without re-adding the sub |
| 10 | TUN engine as a strategy: `tun-type: [singbox, tun2proxy, default, xray]`, `tun-mode: [system, gvisor]` | Happ desktop third-party libs + app-management params | let a provider switch stacks when kernel routing fights (macOS/Docker) |
| 11 | Geo handling: zstd-packed geo assets, per-profile trimming (`cutGeoData`, `analyzeGeoIP/Site`), 3-minute download deadline → red badge, geo refresh ≤1×/week, matcher cache | `libzstd-jni` in Happ APK; Incy `cutGeoData`/`loadGeoStatsCache`; Happ routing doc | smaller APK, faster start, visible failure state |
| 12 | Memory knobs for the core (`initMemoryManagement`, `gcPercent`, `maxProcs`, `no-limit-enabled`) | Incy API; Happ `no-limit-enabled` / `no-limit-xhttp-enabled` | the "xhttp needs more RAM" failure mode becomes a param, not a build |
| 13 | `findProcessByConnection` — attribute a live connection to a package | `libxray_Libxray$proxyProcessFinder_findProcessByConnection` | enables a real per-app connections screen |
| 14 | Opaque share links with a public encoder: `incy://crypt1/<payload>` (npm + PHP, same wire format) | `INCY-DEV/incy-link-encoder` | we can ship an encrypted sub link without inventing or borrowing Happ's key-exchange |

Explicit non-recommendation: Happ's `happ://crypt4/crypt5` scheme relies on RSA keys baked into the
APK, is documented as extractable, and their own docs ask assistants not to help defeat it. Use the
Incy encoder pattern (open format, our own keys) instead.

---

## 7. Unverified / open

- Happ per-node sweep: temporary core per node vs one core with N inbounds. Symbols only prove the
  API exists (`measureOutboundDelay[-WithType]`); Go symbols stripped. **UNVERIFIED**
- `server_flag` as a Happ meta key: single string-pool hit, no doc, no sample. **UNVERIFIED**
- Incy "Rust-core" completeness: strings show `... is not implemented by this Rust core`, gVisor
  fallback and Go packages linked, so the Rust core likely covers a subset. **UNVERIFIED**
- Whether either client enforces an authenticated API inbound on mobile: Happ was documented
  (Apr 2026) as enabling the Xray API *without* auth; the current APK has no `api.services` guard
  string of its own, and the desktop doc advertises no API setting. **UNVERIFIED**
- Happ iOS DNS handling differs from Android (bug report: "Failed to configure DNS from JSON,
  default DNS was applied" on a config that passes `xray run -test`). **Behaviour documented by a
  third party, not reproduced.**
