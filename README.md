<div align="center">

<img src="assets/logo/icon-master-1024.png" width="128" alt="Nabız icon">

# Nabız

**Your Mac and your phone, at a glance — on each other's screen.**

A native macOS menu bar monitor and an Android companion that show each other's CPU, memory, storage, battery and network in real time.
Local network only. No cloud, no account, end‑to‑end encrypted.

[English](#english) · [Türkçe](#türkçe)

![CI](https://github.com/serdarabdulkadir/nabiz/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/license-MIT-black.svg)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black.svg)
![Android 8+](https://img.shields.io/badge/Android-8%2B-black.svg)

</div>

---

## English

### What it does

| | macOS app | Android app |
|---|---|---|
| **Own stats** | CPU (performance / efficiency cores), GPU, memory + pressure, disk, network ↑↓, battery health & cycles, uptime, CPU temperature & fans, top 5 processes, Bluetooth device batteries, 10‑minute history graphs | Battery (level, charging, temperature), memory, storage, network, thermal status, 10‑minute history graphs |
| **Other device** | Phone tab in the menu bar panel | Mac card as a **Live Update** notification (Android 16 `ProgressStyle`, shows on the status bar chip / Xiaomi HyperOS *Super Island*) |
| **Remote actions** | — | Refresh, lock screen, sleep, wake display; Quick Settings tile |
| **Link health** | Round‑trip latency, clear version‑mismatch message | Same, plus latency in the live card |
| **Alerts** | Battery, charging, storage, CPU, memory, thermal and connection alerts with per‑device thresholds, hysteresis and cool‑down | Same alert engine, shown on the phone |
| **Look** | SwiftUI `MenuBarExtra`, Liquid Glass on macOS 26 (material fallback on 15), 6 menu bar styles | Jetpack Compose, light + dark, 5 notification designs |

Honest numbers only: anything that can't be read is shown as `--`. Android 8+ doesn't expose CPU usage, so the phone has no CPU tile.

### Platforms

| Platform | Status |
|---|---|
| macOS 15+ (Apple Silicon & Intel) | ✅ Menu bar app |
| Android 8+ (Live Update on Android 16+) | ✅ App + live notification |
| iOS | 🗺️ Planned — see [Roadmap](#roadmap) |

### How the link works

1. The Mac app advertises `_nabiz._tcp` over Bonjour (port `47821`).
2. The phone discovers it on the same Wi‑Fi and both sides show a **6‑digit code** — confirm it on both.
3. Keys are derived with ECDH P‑256 + HKDF‑SHA256; every message is AES‑GCM encrypted. Pairing keys live in the macOS Keychain / Android Keystore.
4. Away from home? Put both devices on the same [Tailscale](https://tailscale.com) network and enter the Mac's Tailscale address on the phone. Pairing still only happens on the local network.

Full wire format: [`docs/protokol.md`](docs/protokol.md).

### Install

**Prebuilt:** grab `Nabiz-mac.zip` and `nabiz.apk` from [Releases](https://github.com/serdarabdulkadir/nabiz/releases).

- **macOS:** unzip, move `Nabız.app` to Applications. It is ad‑hoc signed (not notarized), so on first launch right‑click → *Open*, or run `xattr -dr com.apple.quarantine /Applications/Nabız.app`.
- **Android:** install the APK (allow "install unknown apps"). Releases from 0.3.0 are signed with the project's release key; if you installed 0.2.0 (debug‑signed), uninstall it first and pair again. On Xiaomi / HyperOS, enable *Autostart* and set battery to *No restrictions* so the live card stays alive — the app links you to both settings.

**From source:**

```bash
# macOS (Xcode 26 / Swift 6 toolchain)
cd mac
swift build && swift test
scripts/paketle.sh --ac        # builds ~/Applications/Nabız.app and opens it

# Android (JDK 17)
cd android
./gradlew assembleDebug testDebugUnitTest
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### Project layout

```
mac/        Swift 6 package: NabizCore (sampling, protocol, alerts — unit tested) + Nabiz (SwiftUI app)
android/    Kotlin + Compose app: stats, peer link, foreground service, live notification
docs/       design language, wire protocol, alert rules
assets/     logo sources
```

### Roadmap

- **iOS companion** — a SwiftUI app sharing `NabizCore` that shows the Mac (and posts a Live Activity). iOS doesn't allow an always‑on background connection, so it needs its own design.
- Home‑screen widget on Android.
- Notarized macOS builds (needs a Developer ID certificate).
- Custom Xiaomi HyperOS *Super Island* layout (needs Xiaomi's focus‑notification allow‑list).

### Contributing

Issues and pull requests are welcome. Please keep the rules in mind:
no invented metrics (`--` when unknown), no new dependencies without a reason, logic in `NabizCore` / plain Kotlin with unit tests, UI only draws.
Run `swift test` and `./gradlew testDebugUnitTest` before opening a PR. Both test suites read the shared protocol fixtures in [`docs/fixtures/`](docs/fixtures), so a wire‑format change on one side breaks the other side's tests.

### License

[MIT](LICENSE)

---

## Türkçe

**Nabız**, Mac ile Android telefonun anlık durumunu (CPU, bellek, depolama, pil, ağ) birbirinin ekranında gösteren açık kaynak bir uygulama çiftidir.

- **Mac:** menü çubuğu uygulaması. Kendi durumunu ve eşleşmiş telefonun durumunu gösterir. macOS 26'da Liquid Glass.
- **Android:** telefonun kendi durumu + Mac'in durumu. Mac kartı kalıcı canlı bildirimdir (Android 16 Live Update; HyperOS'ta Super Island). Bildirimden yenile, kilitle, uyut, ekranı uyandır.
- **Bağlantı:** yalnız yerel ağ (Bonjour), 6 haneli kodla eşleşme, uçtan uca şifreli. Bulut ve hesap yok. Evden uzaktayken Tailscale.
- **Uyarılar:** pil, şarj, depolama, CPU, bellek, ısınma ve bağlantı için cihaz başına eşik.

Kurulum için yukarıdaki *Install* bölümüne, protokol için [`docs/protokol.md`](docs/protokol.md), tasarım dili için [`docs/tasarim.md`](docs/tasarim.md) dosyasına bakın. iOS sürümü yol haritasında.

Lisans: MIT.
