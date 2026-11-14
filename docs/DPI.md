# DPI evasion: design and platform matrix

Portal client must work in two hostile networks at once: Russia (TSPU) and China (GFW).
Both filter TLS by SNI/ClientHello, so three independent mechanisms are in scope, and they
must not be confused with each other.

Status: design. Facts marked **[verified]** were checked against the repos/releases listed at
the end; everything marked **[check]** must be confirmed before it ships.

## 1. Three layers, three different mechanics

| Layer | What it does | Where it sits | Privileges |
|---|---|---|---|
| `finalmask` (in Prizrak-Core) | fragments / reshapes the TLS ClientHello (tlshello fragment, `xmc`, `sudoku`, `noise`, `udhop`, `quicParams`) | inside the core, all platforms | none |
| ByeDPI (`hufrea/byedpi`) | userspace SOCKS proxy that opens the connection to the node itself with desync / OOB / fake-TLS strategies | local `socks5` outbound, chained through `dialer-proxy` | none for most strategies |
| zapret (`bol-van/zapret`) | packet-level mangling of outgoing TCP/UDP (nfqws on nftables, winws on WinDivert) | transparent, no proxy; kernel/packet filter | root / administrator |

Consequence: ByeDPI is applied **to the node connection**, not to the payload inside the tunnel.
The core therefore needs `dialer-proxy` on the proxies (or on a group), pointing at the local
ByeDPI SOCKS. zapret needs nothing in the config — it mangles the packets the core sends anyway.

## 2. Platform matrix

| Platform | finalmask | ByeDPI | zapret | Notes |
|---|---|---|---|---|
| Android | yes | yes — `libbyedpi.so`, no root | only with root (Magisk) | ship ByeDPI by default, hide zapret unless root detected |
| Windows | yes | yes — releases `x86_64-w64`, `i686-w64` **[verified]** | yes — `winws` + WinDivert, needs admin | two options; see §4 |
| Linux | yes | yes — `x86_64`, `aarch64`, `armv7`, `mips` **[verified]** | yes — `nfqws`, root | router and desktop share the same binaries |
| macOS | yes | **no release binary** **[verified]** — build from source, C, `[check]` privileges per strategy | **not supported upstream** **[verified]** — `[check]` whether a maintained pf/divert fork exists | only finalmask + ByeDPI-from-source |
| OpenWrt / Merlin (routers) | yes (core) | yes | yes — `openwrt-embedded` tarball **[verified]** | zapret is the natural router choice |
| iOS | yes | no (no raw sockets, no background process) | no | finalmask only |

`zapret` upstream releases ship `zapret-*.tar.gz`, `zapret-*.zip` and a separate
`openwrt-embedded` archive; there is no macOS asset **[verified]**.

## 3. What the app must own

```
DPI Engine (one service per platform)
├─ detect capabilities: root/admin?, engine binaries present?, core supports finalmask?
├─ start/stop engine, health-check by port (ByeDPI) or process (zapret)
├─ inject into the core config:
│    ByeDPI  -> proxies: [{name: "dpi-<strategy>", type: socks5, server: 127.0.0.1, port: N}]
│                and dialer-proxy: "dpi-<strategy>" on the selected proxies/group
│    zapret   -> nothing (transparent), only report status
└─ publish state upward: OFF / STARTING / RUNNING(strategy) / FAILED(reason)
```

Strategies are **data, not code**: `assets/dpi/strategies/*.json` (one entry per preset with
engine, argv, port, target platforms, notes). Presets RU and CN ship in the repo; users can add
their own the way zapret users already share lists.

UI: one switch "Обход DPI" + strategy list; the switch reads its state from the running engine,
never from a saved flag. If the engine is not available for the platform, the switch is hidden
rather than shown as broken.

## 4. Windows: two engines, different trade-offs

- `zapret/winws` — best coverage, needs administrator once per session (UAC), no proxy chaining.
- ByeDPI `x86_64-w64` — no admin, but only covers connections that go through its SOCKS, so the
  core must be pointed at it with `dialer-proxy`.

Both should be offered: zapret as "рекомендуется", ByeDPI as "без прав администратора".

## 5. macOS caveat

There is no upstream zapret for macOS, and ByeDPI ships no darwin binary. So on macOS the honest
default is `finalmask`; ByeDPI has to be compiled in CI and its strategies verified one by one.
**[check]** Whether desync strategies rely on raw sockets that need root on Darwin.

## 6. Interaction with the panel config

The panel profile already contains groups and rules. DPI must not rewrite them: it only adds
proxies and `dialer-proxy` fields. The injection layer must therefore be a structured YAML edit
(parse → modify → serialize), not the string surgery used by the old Android client.

## 7. Open questions

1. Which ByeDPI strategies actually pass TSPU today, and which pass GFW today? Needs a measured
   matrix per region, not a list from a blog.
2. Does Prizrak-Core's `finalmask` cover the same cases as `--split-pos`/`--oob` desync, or only
   fragmentation? Needs a test against the same hosts.
3. zapret on Android: root-only means we need a clear "почему недоступно" explanation, not a
   silent absence.

## Sources checked

- `hufrea/byedpi` releases v0.17.3 — asset list (linux + windows, no darwin) **[verified]**
- `bol-van/zapret` releases v72.13 — `tar.gz`, `zip`, `openwrt-embedded`; no macOS **[verified]**
- Prizrak-Core `README` / outbound list for finalmask family **[verified]**
