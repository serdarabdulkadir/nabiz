# Nabız

Mac ile Android telefonun anlık durumunu (CPU, RAM, disk, pil, ağ) iki yönlü gösteren uygulama çifti.

- **Mac (`mac/`)**: menü çubuğu uygulaması. Mac'in kendi durumunu gösterir (Stats ve benzeri uygulamaların yerine geçer) ve eşleşmiş telefonun durumunu gösterir.
- **Android (`android/`)**: kendi durumunu ve Mac'in durumunu gösterir. Mac kartı kalıcı ve canlı bir bildirimdir (Android 16 Live Update, `Notification.ProgressStyle`).
- **Kanal**: yerel ağ, Bonjour ile bulma, 6 haneli kodla eşleşme, şifreli WebSocket/TCP. Bulut yok. Ayrıntı: `docs/protokol.md`.

## Yerine geçtiği uygulama
`/Applications/State.app` (Better365 State 2.1.9, `com.better365.menubar`). Karşılanacak izleme özellikleri: CPU (P/E çekirdek), GPU, bellek, disk, ağ, pil, sıcaklık, fan, Bluetooth cihaz pilleri, çalışma süresi. State'in ekstraları (ekran/klavye temizleme, Dock kilidi, kısayollar, bellek boşaltma) kapsam dışı.

## Fazlar
1. Mac menü çubuğu (yalnız Mac'in kendi durumu) → State silinebilir.
2. Kanal + Android uygulaması + Mac canlı bildirim kartı.
3. Ters yön: telefon durumu Mac panelinde. Sonra sıcaklık/fan ayrıntısı, Bluetooth cihaz pilleri.

## Teknik
- Mac: Swift 6, SwiftUI `MenuBarExtra` (`.window`), SwiftPM paketi + `scripts/paketle.sh` ile `.app`. Hedef macOS 26+ (Liquid Glass), eski sürümde `.regularMaterial` yedeği.
- Android: Kotlin + Jetpack Compose, minSdk 26, targetSdk 35+. Ön plan servisi (`dataSync` / `connectedDevice`) bildirimi günceller.
- Ortak sözleşme: JSON mesajlar, şema `docs/protokol.md`. İki taraftaki model alanları aynı adlarla tutulur.

## Tasarım
Kaynak: `docs/tasarim.md`. Mac tarafı ORBIO (`~/Library/bt-ekosistem`) menü paneliyle aynı dildedir: Liquid Glass karolar, halka göstergeler, hap seçiciler. Android tarafı ORBIO Android paletini kullanır. ORBIO bizim kodumuz; `GlassStyle.swift`, `Tiles.swift` (BatteryRing), `PeerTransport.swift` gibi dosyalar örnek alınabilir ya da sadeleştirilerek taşınabilir. ORBIO'ya YAZILMAZ.

## Kurallar
- Uydurma metrik yok: okunamayan değer `--` gösterilir. Android 8+ CPU kullanımını vermez; Android'de CPU kartı yoktur.
- Varsayılan güncelleme: panel/ekran açıkken 2 sn, kapalıyken 10 sn. Bildirim saniyede 1'den sık güncellenmez.
- Telefon tarafında hassas izinler (bildirim erişimi, arama yönetimi, kişiler, arama geçmişi) yalnız "Mac ile paylaş" anahtarlarıyla ve **varsayılan KAPALI** istenir (2026-11-19, ORBIO modeli). Mac bu verileri diske yazmaz. Ayrıntı: `docs/protokol.md` bölüm 10.
- Commit / push / yayın yalnız kullanıcı onayıyla. Sır (anahtar, token) repoya girmez; eşleşme anahtarı Keychain / Android Keystore'da.

## Ekip ve akış
- Ana oturum: plan, dosya listesi, son kontrol.
- Kod: `mac-gelistirici` (Swift) ve `android-gelistirici` (Kotlin), en çok ikisi paralel, aynı dosyaya iki ajan yazmaz.
- Sonra global `dogrulayici` (build + test) → `inceleyici`.
- `dis-danisman`: Claude token'ı harcamadan Antigravity (`.claude/bin/ag.sh`, uygulama açık olmalı) ya da Cursor CLI ile tarama, ikinci görüş, uzun log özeti.
- Ajanlar Sonnet / Haiku; Fable kullanılmaz (maliyet).
- Kullanıcı token'a duyarlı: arada derleme yok, iş sonunda tek build + test.

## Komutlar (kuruldukça güncellenir)
- Mac: `cd mac && swift build`, `swift test`, `scripts/paketle.sh --ac`
- Android: `cd android && ./gradlew assembleDebug testDebugUnitTest`, kurulum `adb install -r app/build/outputs/apk/debug/app-debug.apk`
