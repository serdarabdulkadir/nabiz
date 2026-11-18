# Tasarım

Ölçü ve dil ORBIO'dan gelir (`~/Library/bt-ekosistem`: `Sources/BTEkosistem/GlassStyle.swift`, `Tiles.swift`, `PanelView.swift`; Android `ui/theme/Theme.kt`). Yeni dil icat edilmez.

## Mac: menü çubuğu
- **Menü çubuğu öğesi**: kompakt metin, örneğin `CPU 23% · RAM 61%`. Kullanıcı hangi modüllerin görüneceğini seçer (CPU, RAM, disk, pil, ağ, telefon pili). Rakamlar `monospacedDigit`. Telefon bağlıysa sonda `iphone` yerine `smartphone` simgesi ve telefonun pili.
- **Panel**: 344 pt genişlik, `MenuBarExtra(.window)`. Üstte hap seçici **Bu Mac | Telefon** (ORBIO'daki "Kulaklık | Telefon" gibi).
- **Bu Mac sekmesi**:
  - 2x2 cam karo ızgarası, her karoda halka gösterge (`BatteryRing` ölçüsü: 54 pt, 5 pt çizgi). Karolar: CPU, Bellek, Disk, Pil.
  - Altında tam genişlikte karolar: CPU çekirdek çubukları (P/E ayrı), bellek basıncı, ağ ↑↓ hızı, pil ayrıntısı (döngü, sağlık, kalan süre sistem veriyorsa).
  - İsteğe bağlı: en çok CPU yiyen 5 süreç.
- **Telefon sekmesi**: aynı ızgara: Pil (şarj, sıcaklık), Bellek, Depolama, Ağ. CPU karosu yok. Bağlı değilse eşleşme kartı (6 haneli kod).
- Renk: sistem renkleri ve beyaz/gri halkalar; anlam rengi yalnız kritik değerde (pil ≤ %20, disk ≥ %90, bellek basıncı kırmızı) `systemRed`, şarjda `systemGreen` şimşek.
- Yalnız koyu tema (ORBIO kararı), Liquid Glass; macOS 26 altında `.regularMaterial`.
- Ayarlar penceresi: ORBIO Ayarlar düzeni (NavigationSplitView + grouped Form): Genel (girişte başlat, yenileme hızı), Menü çubuğu (modüller), Telefon (eşleşme, unut).

## Android
- Palet ve ölçü ORBIO Android `Theme.kt` (monokrom, tek vurgu, köşe 8/12/28, 4 tabanlı boşluk). Açık + koyu.
- Ana ekran: üstte segment **Telefon | Mac**, altında karolar (Mac sekmesinde CPU dahil).
- **Canlı bildirim kartı (Mac)**: `Notification.ProgressStyle` (Android 16), AimTrack bildirimiyle aynı yapı:
  - Başlık: Mac adı · pil yüzdesi (şarjdaysa ⚡ değil, sistem simgesi).
  - Metin: `CPU 23% · RAM 61% · Disk 72%`.
  - İlerleme: kritik değer olan metrik ya da CPU; segmentler eşik renginde.
  - Butonlar: Yenile, Mac'i kilitle, Uyut (son ikisi Mac onayı gerektirmez ama ayarlardan kapatılabilir).
  - Android 16 altı: aynı içerik standart `BigTextStyle` + ilerleme çubuğu.
- Telefonun kendi kalıcı bildirimi yok (gereksiz); yalnız Mac kartı.

## Yasaklar (ORBIO ile aynı)
Mor-mavi gradyan, neon, emoji, sahte 3D, her şeyi kart içine koymak, büyük boş kahraman alanı, boş laf metin.

## Görsel dil (2026-11-18)
- Token'lar `mac/Sources/Nabiz/DesignTokens.swift`: `Radius` (tile 22, group 18, card 16, row 10; hepsi `.continuous`), `Palette` (fill, track, selection, uyarı turuncu, kritik kırmızı, şarj yeşil), `Thresholds.warning` (%75), `Motion`.
- Eşmerkezli köşe: dış yarıçap = iç yarıçap + padding. Panel padding 12, karolar 22, satır grupları 18, hap ve çubuklar Capsule. Settings'te kutu/kartlar tek ölçek: card 16, iç öğe 10.
- Renk: halka normalde `primary`, izi `Palette.track`; CPU/bellek/disk >= %75 turuncu, kritik kırmızı, pilde yalnız kırmızı (<= %20), şarjda yeşil şimşek. Halka aynı rengin %70-%100 opaklığında AngularGradient.
- Rakam: `.rounded` + `monospacedDigit`, `.contentTransition(.numericText)`; halka `trim` değişimi `.smooth(0.5)`.
- Animasyon eğrisi: `.spring(response: 0.35, dampingFraction: 0.82)`. Hap seçici (`SlidingPillPicker`, panel ve Ayarlar araç çubuğu) tek kapsülü `matchedGeometryEffect` ile kaydırır; basılıyken 0.96 ölçek, seçimde `.sensoryFeedback(.selection)`.
- İçerik geçişi yönlü: yeni sekme ~16 pt kayarak + opaklık + blur 4 -> 0 gelir, eskisi ters yöne gider (yön sekme sırasından). Panelde ZStack kalır (yükseklik oynamaz), Ayarlar'da `.id(tab)` + `.transition(.directional)`.
