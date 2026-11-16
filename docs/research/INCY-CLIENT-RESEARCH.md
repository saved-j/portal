# INCY (llc.itdev.incy) — subscription format + latency-test mechanism

Research target: what we can lift from INCY into Portal. Everything below is evidence-backed unless marked **UNVERIFIED**.

## Evidence base

| Source | What |
|---|---|
| `https://docs.incy.cc/llms-full.txt` (234 KB, RU) | Official developer docs, generated from `github.com/INCY-DEV/incy-docs`. Saved locally: `~/.hermes/cache/scratch/incy/llms-full.txt` |
| `https://github.com/INCY-DEV/incy-platforms` release `android-v4.0.1` → `Incy.apk` | SHA-256 `1d4bf483dbceafc7ff212a3ea3cc9fdfc72d198d43c0f75b1887637178eb3c3d` (matches published `SHA256SUMS`) |
| jadx 1.5.6 decompile of `classes.dex/2/3` | `~/.hermes/cache/scratch/incy/src3`, `src12` (paths quoted as `src3/sources/<pkg>/<file>.java:line`) |
| `lib/arm64-v8a/libgojni.so` (stripped, Go+Rust) | Go funcnametab + Rust string pool mined via raw byte scan |

App identity: package `llc.itdev.incy`, developer LLC ITDEV, Android 4.0.1 / desktop 3.9.1. Native app (**not** Flutter): Kotlin + Compose, JNI into a c-shared Go library.

## 1. Core: Xray for serving, "Ferrum" (Rust xray re-implementation) for probing

- Docs/README say "Cross-platform proxy client built on **Xray-core**".
- The shipped `.so` links **two engines**:
  - Go wrapper `incycore` calling `xray_start/xray_stop/xray_version/xray_query_stats` — linked `-lxray_ffi` (build tag `ferrum,http2legacy`, version string `2.4.5-ferrum.13`, go build path `/home/runner/work/incycore-build/.../VpnCore`).
  - A **Rust** xray clone (`/tmp/umya-ferrum-target/...`, crates `crates/proxy/vless`, `crates/transport/xhttp|reality|hysteria|quic|kcp|finalmask`, `crates/app/observatory`, `crates/core/src/probe.rs`). Same module paths as `xray-core` (gVisor `pkg/tcpip` netstack, `Xray.App.Observatory` protos).
- Error strings confirm the split: `"ferrum experimental: config ping unavailable while VPN is running (single-instance core)"`, `"probes require a disposable worker without a live instance"`, `"an instance is already running; xray_stop it first"`.

**Takeaway:** probing gets its own throwaway engine instance; the Rust engine exists so a probe batch can start/stop in ms without touching the live connection.

## 2. Subscription body formats — accepted ladder

Docs (`subscription-format.md`) + parser `pg/f.java`, `pg/d0.java`.

### 2.1 Formats accepted

1. **base64 of link list** (one URI per line). URL-safe accepted (`-`→`+`, `_`→`/`), padding optional (`pg/f.java:366 a()` re-pads to a multiple of 4).
2. **plain link list**.
3. **JSON** — either a single full xray config object or an **array of full configs** (one entry = one server).
4. **Mixed**: links + `://routing/…` directive lines + `#key: value` metadata lines + `#announce:`.
5. **Raw WireGuard/AmneziaWG `.conf`** (multi-line INI), or one `.conf` → one server.
6. **AmneziaWG JSON container** `{"type":"amneziawg","version":1,"servers":[{"name","config"}]}` — usable standalone or as one element inside the config array.

Not parsed (recognised and skipped): `ssr://`, `tuic://`, `hysteria://`.

### 2.2 Body sniffing (worth copying verbatim)

`pg/d0.java:29 a()`:
1. trim body;
2. if it does **not** start with `{` or `[`: try `o(body)` — plain base64 decode, then URL-safe decode; accept only if decoded text has **no control chars** other than `\n\r\t` (`pg/d0.java:540 o()`) — this is what stops random text being "decoded" into garbage;
3. if that fails: **strip every non-base64 character** from the body (keep `A–Z a–z 0–9 + / = - _`) and decode *that* — recovers base64 bodies wrapped in quotes/JSON string escapes/CRLF;
4. on total failure return the original string (then treated as JSON/conf/plain).

### 2.3 Full xray config detection & normalisation

- A JSON object is a "full config" iff it has **both** `inbounds` and `outbounds` (docs `full-xray-config.md`).
- Array element → one server entry. Parse rule (`pg/f.java:585 l()`):
  - `name = obj.optString("remarks", "")`; if empty → name of the parsed outbound.
  - `meta = obj.optJSONObject("meta")`; `desc = meta.optString("serverDescription")` (base64-decoded in `pg/f.java:458 d()`); falls back to the outbound's own description.
  - iterate `outbounds[]`: **skip** `loopback, freedom, blackhole, dns`; **only accept** `vless, vmess, trojan, shadowsocks, hysteria, hysteria2, socks, http, wireguard`; **first successfully parsed outbound wins**, `break`.
  - No parsable outbound → element dropped (not an error).
- After import, the stored blob is **cleaned**: `pa/o.java:8 a()` removes top-level `remarks` and `meta.serverDescription` (drops `meta` if it becomes empty). Name/desc live in DB columns; the JSON stays byte-faithful otherwise → this is what makes re-export/backup idempotent.

### 2.4 Runtime patching of full configs (`patchFullConfigInbounds`, docs §Автоматический патчинг)

- `socks`/`mixed`/`http` inbounds: `listen` forced to `127.0.0.1` (port untouched — config must use 10808 socks/mixed, 10809 http). Creds injected on inbound if it has none.
- If no socks-like inbound exists → add `mixed` on `127.0.0.1:10808` with sniffing.
- `burstObservatory`/`observatory` present but no `stats` → add `"stats": {}`.
- observatory **and** balancers present → prepend `routing.rules` entries forcing the DNS server IPs out via `direct` (breaks the observatory→DNS→balancer cycle); auto-add a `direct`/`freedom` outbound if absent.
- MPH cache disabled for full configs (`mph_cache.dat` deleted); geo trimming skipped (provider ships own geo files); `fakedns` pool narrowed.
- Stored as one opaque `fullConfigJson` column on the server model.

### 2.5 Per-server name/description grammar (very cheap to support)

```
vless://…:443?…&security=tls#Germany%20only%20Wi-Fi?serverDescription=SGlnaC1TcGVlZA==
```
- Split at **first** `?` **or** `&serverDescription=`; all before = URL-decoded name; `serverDescription` = base64 (URL-safe, NO_WRAP) ≤30 chars (`pg/f.java:558 k()`).
- vmess variant: `base64url({…})` with extra `meta.serverDescription` key.
- vmess bulk upload supports a **zlib envelope**: 4-byte big-endian uncompressed length + zlib stream, detected by `byte[4] == 0x78`; capped 1 MiB (`pg/f.java:406 b()`).

## 3. Subscription HTTP contract

Request headers sent by the client (`pg/a0.java:45 c()`):

```
User-Agent: INCY/<version>/<platform> Dalvik/...       (e.g. "INCY/4.0.1/android")
Accept: */*
Accept-Language: <device BCP-47>
x-app-version, x-device-locale, x-client: INCY
x-hwid, x-device-os, x-ver-os, x-device-model          (only when HWID sharing enabled)
```
`Accept-Encoding` only on iOS (gzip, deflate, br). OkHttp cache handles `ETag`/`If-None-Match`/`If-Modified-Since` (`kh/b.java:268`).

Response headers that matter (authoritative table in `app-management.md`):

| Header | Notes |
|---|---|
| `profile-title` (alias `subscription-name`, fallback `content-disposition`) | ≤25 chars, `base64:` prefix = name\n+description |
| `profile-description`, `support-url`, `support-email` | `support-email` is the only way to show the Email button |
| `profile-update-interval` (hours), `routing-geo-update-interval` (0–8760) | user local value wins for geo |
| `subscription-userinfo: upload=;download=;total=;expire=` | `expire > 32e9` ⇒ interpreted as ms and divided; **literal `0` ⇒ hide the whole traffic block** |
| `sort-order: none|ping|name` | per-subscription on mobile, global on desktop |
| `announce`, `announce-url` | announce clipped to 5 lines |
| `hide-url`, `hide-check` | tri-state 1/0/absent; `hide-check` = hide the "Проверить" (connection check) button |
| `routing` / `autorouting` | `autorouting` must be a full `incy://autorouting/onadd/https://…` URI (bare URL rejected); `routing: off` disables built-in routing |
| `new-domain` / `new-url` | migrate this subscription's URL after domain-ownership check |
| `fragmentation-*`, `noises-*`, `server-address-resolve-*`, `per-app-proxy-*` | provider-forced transport knobs |
| `banner-*`, `expiry-banner-*`, `premium-url` | in-app promo surfaces |

Body `#key: value` lines carry the **same** keys as fallback (headers win). Also `hide_url`/`hide_check` can be regex-scraped straight out of a JSON body (`pg/d0.java:189 c()` scans `"hide_url"\s*:\s*(true|false)` before any real JSON parse).

Fallback hosts: `settings.fallbackHosts[]` from the premium config, replayed on network/timeout/5xx/429 — **never** on 404/410. Only the host changes, path/token kept.

## 4. How it tests all servers (the interesting part)

### 4.1 Five ping modes, user-selectable per subscription

`incy`, `tcp`, `proxy_head`, `proxy_get`, `icmp` — labels `INCY Ping`, `TCP Connect`, `HTTP GET`, `HTTP HEAD`, `ICMP Ping` (`mg/p3.java:10`, `bh/x.java:604`, `dh/g3.java:795`).

- `pingTestUrl` is only honoured for `incy|proxy_head|proxy_get` (`llc/itdev/incy/domain/model/c.java:31`).
- **INCY Ping** = real HTTP GET through the proxy, then **the measured RTT is divided by 3.3** `Math.max(1, rint(ms/3.3))` (`jg/e0.java:49 j()`), so the number looks like ICMP rather than a full proxied round-trip. Docs say the same in prose.
- **TCP** = plain `Socket.connect(host, port, timeout)` with `IncyCore.protectSocket()` first (keeps the probe out of the live TUN), and `>= 10000 ms` is treated as failure (`dh/w.java`, case 2).
- Native constants: `PingDelayError = 10000`, `PingDelayTimeout = 11000` (`incycore/Incycore.java`).
- Display formats: `time` | `bars` | `both` | `dots` (dots = iOS only).

### 4.2 Two-layer scheduler

**Outer layer — 4-way parallel map with streaming results** (`oa/fd.java`, decompiled to clean Kotlin):

```kotlin
suspend fun <T, R> mapParallel(
    list: List<T>, parallelism: Int,
    onEach: suspend (T) -> R?, onResult: suspend (R) -> Unit,
    timeoutMs: Long
): List<R> {
    require(parallelism > 0 && timeoutMs > 0)
    if (list.isEmpty()) return emptyList()
    val cursor = AtomicInteger()
    val dispatcher = Dispatchers.limitedParallelism(min(parallelism, list.size))
    val results = arrayOfNulls<R>(list.size)          // input order preserved
    withTimeout(timeoutMs) {                           // global budget
        // N workers: i = cursor.getAndIncrement(); results[i] = onEach(list[i]); onResult(r)
    }
    return results.filterNotNull()
}
```
Call site: `jg/e0.java:35 f(list, timeoutSec, url, onResult, cont)` → `mapParallel(list, parallelism = 4, …, timeoutMs = 120_000)`.
Because `onResult` fires per completed probe, the list repaints **row by row** as answers land; nothing waits for the slowest server. Results are index-aligned, so the UI never has to re-sort to place a number.

**Inner layer — isolated worker processes.** `jg/e.java` binds **four** AIDL services `FerrumPingService0..3` (declared in a 4-thread dispatcher, `5 s` start timeout, `IllegalStateException("Ferrum ping service startup timed out")`) over interface `llc.itdev.incy.core.IIncyCoreBridge`. Each worker: start disposable Ferrum core → probe batch → tear down.

**Large payload transfer:** the config array is **not** sent through the Binder parcel — it is streamed as JSON over a `ParcelFileDescriptor` pipe (`ParcelFileDescriptor.AutoCloseInputStream`, 8 KiB buffered, `bh/e0.java:93`), dodging the ~1 MB transaction limit.

Batch handler (`bh/e0.java`):
1. read array from pipe;
2. per element `IncyCore.preparePingConfig()` — strips internal key `_incyPingGeoDirectory`, ensures ping geo assets, rewrites geo paths to `__incy_ping_<sha256[:12]>` (symlinked `geoip.dat`/`geosite.dat`, `jg/n0.java`);
3. clamp timeout: `<=0 → 3 s`, else `min(t, 30) s`;
4. `Incycore.pingConfigs(configsJson, timeoutSec, testUrl)` → JSON string;
5. return `""` on any throw.

Single-server path: `IncyCore.testLatency(configJson, protocol, timeoutMs = 5000)` (default 5 s), coroutine on `Dispatchers.IO`.

### 4.3 Native probe contract (`libgojni.so`)

Go API surface: `ping`, `pingConfig(configJson, protocol, url, ?)`, `pingConfigs(configsJson, timeoutSec, testUrl)`, `pingConfigsBatchSync`, `pingProxy`, `pingXray`, `measureDelay(fd, url, ?)`, plus callbacks `PingCallback.onPingResult(index, delay, error)` / `onPingComplete()`.

Probe request JSON (string literals in the Rust/Go pool): `{"configs":[…], "url": …, "timeout_ms": …, "asset_path": …}`; validation errors `"url is required"`, `"configs must be an array"`, `"config has no outbound"`. Internal outbound tag **`__probe_default`**. Default destination: `https://connectivitycheck.gstatic.com/generate_204` and the probe **requires a 204** ("destination url, need 204 for success return"). Failure modes: `"HTTP probe timed out"`, `"probe request is NULL"`, `"Ferrum probe batch failed"`.

### 4.4 Result acceptance rules (blunt, worth copying)

`jg/j0.java:10` parses the engine's JSON array; each element `{"Index", "Delay", "Error", "Address"}`.

A probe counts as **success** only when all hold:
- `Error` key **present and not JSON-null** (engine must have explicitly reported), and its trimmed value is empty;
- `1 <= Delay < 2^31`;
- if the `Error` key was absent: additionally `Delay < 10000`.

Duplicate `Index` → first wins. Gaps are filled with `"Missing engine result"`; an unparsable/absent array → `"Engine unavailable or invalid response"`. Output list is always re-indexed `0..n-1` so the UI can zip it against the server list.

### 4.5 Settings that drive it

Per-subscription DB columns (`SubscriptionEntity`): `pingProtocol`, `pingTestUrl`, `pingDisplayFormat`, `serverSortOrder`, plus `perAppProxy*`, `hideUrl`, `hideCheck`, `fallbackHostsCsv`, `keepExpanded`, `showOnHome`.

Premium-config defaults (first connect only, user can override; override flags stored as `pingProtocolOverride_<id>` etc., `ah/q2.java:4775`): `defaultPingProtocol`, `pingTestUrl`, `defaultSortOrder`, `defaultPingDisplayFormat`, `pingOnUpdate` (auto-ping all servers after a subscription refresh). Global pref keys also include `ping_on_launch`, `ping_timeout`, `ping_display_format`.

## 5. Server list UI behaviour

- **Grouping = one collapsible card per subscription** (no protocol/region grouping). `keepExpanded`, `showOnHome`, `orderIndex` on both subscription and server rows.
- **Order**: provider order by default (`orderIndex`), else `ping` (fastest first) or `name`. On mobile the choice is per subscription; on desktop it is global.
- **Row**: name, optional `meta.serverDescription` subtitle, latency cell, per-server `isActive`, `lastConnected`, persisted `latency` (survives restarts), custom user description (`customDescription`).
- **Badges** (security/transport chips) are hidden for full-config entries — the config is opaque, so no chip can be truthful.
- **Network gating by exact name labels** (Premium): `only Wi-Fi` / `only Mobile` anywhere in the name hides the server on the other network type. Case/hyphen sensitive; Ethernet counts as Wi-Fi; unknown network type → filter is a no-op. Desktop re-checks interfaces every ~10 s.
- Latency rendering: `time` (ms number), `bars`, `both`, `dots`.

## 6. Steal list for Portal (ranked by value/effort)

1. **`mapParallel(list, 4, onEach, onResult, 120s)`** — atomic-index worker loop + index-aligned results + per-result callback + one global `withTimeout`. This alone gives "test all servers" that feels instant and never blocks on one dead node. ~60 lines.
2. **Result acceptance rules** (§4.4) — stops the UI showing `0 ms` or `12345 ms` as a win, and makes "engine lied / engine died" distinguishable from "server dead".
3. **`/3.3` normalisation for proxy-ping** — one line that makes HTTP-through-proxy numbers comparable to ICMP so users don't think the client is slow.
4. **Per-subscription** `pingProtocol`/`pingTestUrl`/`pingDisplayFormat`/`serverSortOrder` (not global) + premium defaults merged with explicit user-override flags.
5. **Body sniff ladder** (§2.2) incl. the strip-non-base64 fallback and the control-char sanity gate — this is why INCY eats malformed panels without erroring.
6. **`#name?serverDescription=<b64>`** fragment grammar + `remarks` / `meta.serverDescription` for full configs; strip both on store, keep them in columns.
7. **Stream config array over a pipe fd** to the helper process instead of a Binder/bundle payload (only matters if we ever move probing out-of-process; on desktop it is moot).
8. **`__probe_default` + disposable probe instance** — start, probe, kill; refuse to probe while an instance is live rather than multiplexing into the user's session.

## 7. Gaps / UNVERIFIED

- **UNVERIFIED** whether iOS/desktop use the same 4-worker + 120 s scheme — only the Android APK was decompiled (`incy-linux` is closed source; only binaries ship).
- **UNVERIFIED** which caller uses native `pingConfigs` (batch) vs `pingConfig` (single, 5 s) for the `pingOnUpdate` path; both are reachable, batch is what the isolated worker calls.
- **UNVERIFIED** the ICMP path: no Android code found for it besides the label — presumably Go `ping`/raw socket behind `protocol=icmp`; it does not appear in the Android ping-protocol list in settings (`mg/p3.java:10` lists only 4 modes) but does in `bh/x.java:604`.
- Docs describe `hide-check` as hiding the "Проверить" **connection check** button, not the ping sweep — do not conflate them.
- Nothing indicates grouping-by-region, "optimal server" auto-select, or speed tests in the list; only latency.

## 8. Local artifacts

```
~/.hermes/cache/scratch/incy/llms-full.txt      # 234 KB official docs, RU
~/.hermes/cache/scratch/incy/Incy.apk           # 61 MB, sha256 verified vs official SHA256SUMS
~/.hermes/cache/scratch/incy/src3, src12        # jadx output (classes3 / classes.dex+2)
```
