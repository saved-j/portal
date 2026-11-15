<div align="center">

# Portal

**Клиент подписок и сетей порталов, построенный на FlClashX.**
**A subscription and portal-network client, built on FlClashX.**
**基于 FlClashX 的订阅与门户网络客户端。**

</div>

---

## Русский

Portal — мультиплатформенный клиент для подписок и сетей порталов. Это форк
[FlClashX](https://github.com/pluralplay/FlClashX), в котором работают два ядра:
**Prizrak** (сборка mihomo) для маршрутизации по правилам и **Xray** для простого портала.
Один список подписок питает оба ядра, а какое из них несёт трафик, решает приложение.

- Платформы: Android, macOS, Windows, Linux
- Без рекламы, без телеметрии, без аккаунтов
- Лицензия: GPL-3.0

### Сборка

См. [BUILD.md](BUILD.md): там закреплены версии Flutter, JDK, Gradle, Android SDK/NDK, Go и
Rust, приведены команды для APK, deb, rpm, AppImage, Windows и macOS и сказано, что в
репозиторий не попадает (ключ подписи и бинарник Xray — он скачивается по закреплённому
SHA-256).

### Структура

- `lib/` — приложение на Flutter (Dart)
- `core/` — обвязка Go-ядра
- `services/helper/` — привилегированный хелпер для TUN на десктопе (Rust)
- `plugins/` — локальные Flutter-пакеты (окно, трей, прокси, rust_api, wifi_ssid)
- `android/`, `macos/`, `linux/`, `windows/` — платформенные оболочки
- `pipeline/1.01a/` — одна замороженная серия патчей против апстрима FlClashX;
  `./apply.sh 1.01a verify` доказывает деревом, что она воспроизводит продукт
- `pipeline/1.02a/` — следующая серия: по одному патчу на тему, каждый применяется к
  замороженному дереву отдельно

## English

Portal is a multi-platform client for subscriptions and portal networks. It is a fork of
[FlClashX](https://github.com/pluralplay/FlClashX) that runs two cores: **Prizrak** (a mihomo
build) for rule-based routing, and **Xray** for the simple portal. One subscription list
feeds both; the app decides which core carries the traffic.

- Platforms: Android, macOS, Windows, Linux
- No ads, no telemetry, no accounts
- GPL-3.0

### Build

See [BUILD.md](BUILD.md): it pins Flutter, JDK, Gradle, the Android SDK/NDK, Go and Rust,
lists the commands for APK, deb, rpm, AppImage, Windows and macOS, and says what never enters
the repository — the signing keystore, and the Xray binary, which is downloaded and checked
against a pinned SHA-256.

### Layout

- `lib/` — the Flutter application (Dart)
- `core/` — the Go core glue
- `services/helper/` — privileged helper for TUN on desktop (Rust)
- `plugins/` — local Flutter packages (window, tray, proxy, rust_api, wifi_ssid)
- `android/`, `macos/`, `linux/`, `windows/` — platform shells
- `pipeline/1.01a/` — a single frozen patch series against upstream FlClashX;
  `./apply.sh 1.01a verify` proves by tree that it reproduces the product
- `pipeline/1.02a/` — the next series: one topic per patch, each applying to the frozen tree
  on its own

## 中文

Portal 是一个多平台订阅与门户网络客户端，基于
[FlClashX](https://github.com/pluralplay/FlClashX) 分叉，内置两个内核：**Prizrak**（mihomo
构建）负责规则路由，**Xray** 负责简单门户。同一份订阅列表同时供给两个内核，由应用决定谁来
承载流量。

- 平台：Android、macOS、Windows、Linux
- 无广告、无遥测、无账号
- 许可证：GPL-3.0

### 构建

见 [BUILD.md](BUILD.md)：其中固定了 Flutter、JDK、Gradle、Android SDK/NDK、Go 与 Rust 的
版本，列出了 APK、deb、rpm、AppImage、Windows 与 macOS 的构建命令，并说明哪些内容不进
仓库——签名密钥，以及按固定 SHA-256 校验后下载的 Xray 二进制。

### 目录

- `lib/` — Flutter 应用（Dart）
- `core/` — Go 内核封装
- `services/helper/` — 桌面端 TUN 的特权助手（Rust）
- `plugins/` — 本地 Flutter 包（window、tray、proxy、rust_api、wifi_ssid）
- `android/`、`macos/`、`linux/`、`windows/` — 平台外壳
- `pipeline/1.01a/` — 针对上游 FlClashX 的一整套冻结补丁；`./apply.sh 1.01a verify`
  用目录树证明它能复现产品
- `pipeline/1.02a/` — 后续系列：每个补丁一个主题，均可单独应用到冻结的目录树

## License

GPL-3.0. Portal is a fork of [FlClashX](https://github.com/pluralplay/FlClashX), which is a
fork of [FlClash](https://github.com/chen08209/FlClash). See [LICENSE](LICENSE).
