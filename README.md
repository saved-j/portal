<div align="center">

# Portal

**Две сети в одном приложении: правила и портал.**
**Two networks in one app: rules and the portal.**
**一个应用里的两张网：规则路由与门户。**

[![Скачать](https://img.shields.io/badge/download-latest-00F5A0?style=for-the-badge)](https://github.com/saved-j/portal/releases/latest)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue?style=for-the-badge)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-Android%20%C2%B7%20macOS%20%C2%B7%20Windows%20%C2%B7%20Linux-lightgrey?style=for-the-badge)](#платформы)

</div>

---

## Зачем нужен Portal

**Clash-приложения на Mihomo хороши тем, что умеют динамические сплит-туннели: правило решает, что
идёт напрямую, а что через портал. Xray-приложения хороши тем, что быстро подхватывают все обходы,
нужные против блокировок.**

Для серьёзной работы нужно и то, и другое: и новые протоколы, и сплит-туннели. А по уму — в одном
приложении.

Мы сделали **два ядра в одном приложении** на базе [FlClashX](https://github.com/pluralplay/FlClashX),
вдохновившись [MULTICORE](https://github.com/fatyzzz/multicore): **Prizrak** (сборка mihomo) несёт
«Сеть порталов», **Xray** — «Простой портал». Режимы полностью раздельные: свои серверы, свои
замеры, свои настройки. Переключение на горячую — меньше секунды, без перезапуска приложения.
Интерфейс упрощён до двух понятных состояний вместо десятка экранов.

## Два режима

**Сеть порталов** — это когда каждый отдельный сервис по правилам из mihomo-подписки уходит своим
маршрутом. Ютуб через Нидерланды, Телеграм через Польшу, а российские сервисы — через Россию:
вдруг вы уехали в отпуск и нужно зайти в свой банк. Решение принимает правило, а не весь трафик
целиком.

**Простой портал** — классический клиент Xray: почти весь трафик заворачивается в один выбранный
сервер, плюс ряд статических сплит-туннелей, намертво прописанных в конфиге.

Один список подписок питает оба ядра; какое из них несёт трафик — решает приложение, а не подписка.
Если подписка поддерживает только один тип — активным для такой подписки будет только один режим.

## Что уже есть

- Переключение режимов и серверов на горячую, без закрытия портала
- Замер задержки по каждому серверу — из живого ядра, а не отдельным пингом
- Плитка в шторке: включает портал без запущенного приложения
- Автообновление подписки в фоне
- Тёмная тема, анимация реальных соединений, тактильная отдача
- Без рекламы, без аккаунтов, без телеметрии

## Платформы

| Платформа | Статус |
|---|---|
| Android | **готово** — `Portal.apk` (arm64), `Portal_legacy.apk` (arm32), `Portal_universal.apk` |
| macOS | в работе |
| Windows | в работе |
| Linux | в работе |
| iOS | в работе |

Portal Duo для десктопа выйдет на том же двухъядерном движке, что и Android-версия.

## Скачать

Все сборки — на странице [Releases](https://github.com/saved-j/portal/releases/latest).
Каждая собирается из этого репозитория и подписана.

- `Portal.apk` — arm64, для современных телефонов
- `Portal_legacy.apk` — arm32, для старых устройств
- `Portal_universal.apk` — универсальная, если не знаешь, какая нужна

## Сборка

См. [BUILD.md](BUILD.md): там закреплены версии Flutter, JDK, Gradle, Android SDK/NDK, Go и Rust,
приведены команды для APK, deb, rpm, AppImage, Windows и macOS и сказано, что в репозиторий не
попадает (ключ подписи и бинарник Xray — он скачивается по закреплённому SHA-256).

## Структура

- `lib/` — приложение на Flutter (Dart)
- `core/` — обвязка Go-ядра
- `services/helper/` — привилегированный хелпер для TUN на десктопе (Rust)
- `plugins/` — локальные Flutter-пакеты (окно, трей, прокси, rust_api, wifi_ssid)
- `android/`, `macos/`, `linux/`, `windows/` — платформенные оболочки
- `pipeline/1.03/` — текущая серия патчей против апстрима FlClashX: один патч — одна тема,
  каждый применяется к замороженному дереву отдельно

## English

**Clash clients built on Mihomo are good at dynamic split tunnels: a rule decides what goes direct
and what goes through the portal. Xray clients are good at picking up the newest obfuscation
quickly, because that is where it lands first.**

Serious work needs both — new protocols *and* split tunnels — and, honestly, in one application.

Portal runs **two cores in one app**, built on [FlClashX](https://github.com/pluralplay/FlClashX)
and inspired by [MULTICORE](https://github.com/fatyzzz/multicore): **Prizrak** (a mihomo build)
carries the *portal network*, **Xray** carries the *simple portal*. The two modes are fully
separate — their own servers, their own latency figures, their own settings — and switching between
them hot takes under a second, without restarting the app. The interface is trimmed to two
understandable states instead of a dozen screens.

- **Portal network** — each individual service is tunnelled along its own route, as the rules in the
  mihomo profile say: YouTube through the Netherlands, Telegram through Poland, Russian services
  through Russia — for the holiday when you need your own bank. A rule decides, not the whole
  traffic at once.
- **Simple portal** — a classic Xray client: almost all traffic goes into one chosen server, plus a
  set of static split tunnels written into the config for good.

One subscription list feeds both cores; the app decides which core carries the traffic, not the
subscription. A profile that supports only one type makes only one mode active for it.

Next: Portal Duo for Windows, Linux, macOS and iOS, on the same two-core engine.

| Platform | Status |
|---|---|
| Android | **shipped** — `Portal.apk` (arm64), `Portal_legacy.apk` (arm32), `Portal_universal.apk` |
| macOS · Windows · Linux · iOS | in progress |

## 中文

Portal 基于 [FlClashX](https://github.com/pluralplay/FlClashX)，在一个应用里运行两个内核：
**Prizrak**（mihomo 构建）负责「门户网络」的规则与分流，**Xray** 负责「简单门户」。两种模式
完全独立——各自的服务器、各自的延迟、各自的设置——热切换不到一秒，无需重启应用。
Windows、Linux、macOS 与 iOS 版本正在开发中。

## License

GPL-3.0. Portal is a fork of [FlClashX](https://github.com/pluralplay/FlClashX), which is a fork
of [FlClash](https://github.com/chen08209/FlClash). The Prizrak core is a build of
[mihomo](https://github.com/MetaCubeX/mihomo); the simple portal runs
[Xray-core](https://github.com/XTLS/Xray-core). See [LICENSE](LICENSE).
