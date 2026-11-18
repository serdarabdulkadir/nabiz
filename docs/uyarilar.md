# Uyarılar (bildirim kuralları)

Mac ve Android bu belgeyi bire bir uygular. Her cihaz kuralları **kendi ayarlarından** okur ve bildirimi **kendi ekranında** gösterir; kural hem kendi verisine hem eşleşmiş karşı cihazın son `stats` verisine uygulanabilir. Ağ üzerinden kural ya da bildirim taşınmaz.

## Kurallar

Her kuralın iki ayrı örneği vardır: **Mac için** ve **Telefon için** (konu cihaz). Her örnek ayrı açılıp kapanır, ayrı eşiği vardır. Uygulanamayan örnek ayarlarda gösterilmez (ör. telefonda CPU yok).

| id | Ad | Koşul (konu cihazın Snapshot'ı) | Eşik varsayılan | Varsayılan |
|---|---|---|---|---|
| `pil_dusuk` | Pil azaldı | `battery.level <= esik` ve `charging == false` | 20 (5–50) | Mac açık, Telefon açık |
| `pil_doldu` | Şarj doldu | `battery.level >= esik` ve `charging == true` | 100 (80–100) | kapalı |
| `disk_dolu` | Depolama doluyor | `disk.used / disk.total * 100 >= esik` | 90 (70–99) | açık |
| `cpu_yuksek` | İşlemci yüksek | `cpu.total >= esik` kesintisiz `sureDk` dakika (yalnız Mac) | 90 (50–100), 2 dk (1–15) | kapalı |
| `bellek_kritik` | Bellek baskısı | `mem.pressure == "critical"` (eşiksiz; Mac) | – | kapalı |
| `sicak` | Cihaz ısındı | Telefon: `battery.temp >= esik` (°C); Mac: `thermal == "critical"` ya da yoksa uygulanmaz | 42 (35–50) | Telefon açık |
| `baglanti_koptu` | Bağlantı koptu | karşı cihaz `sureDk` dakikadır görülmedi ve son kopuş `uykuyaGidiyor` ile DEĞİL | 10 dk (2–60) | kapalı |

`baglanti_koptu` yalnız karşı cihaz için vardır (kendi cihazın için anlamsız).

## Tetikleme ve tekrar

- Kural **koşul yanlıştan doğruya geçince** bir kez bildirim atar.
- Tekrar atabilmesi için koşulun **kapanması** gerekir; kapanma eşiği histerezisli: `pil_dusuk` için `level >= esik + 5` ya da şarja takıldı; `disk_dolu` için `< esik - 2`; `cpu_yuksek` için `< esik - 10`; `sicak` için `< esik - 2`; diğerleri koşulun yanlış olması.
- Ayrıca aynı kural örneği **30 dakikadan sık** bildirim atmaz (kalıcı zaman damgası).
- Uygulama yeni açıldığında ilk örnekte koşul zaten doğruysa bildirim **atılır** (kullanıcı bilmeli), sonra kurallar normal işler.
- Karşı cihaz verisi yalnız oturum `READY` iken ve son `stats` 2 dakikadan yeniyse değerlendirilir.

## Bildirim metni (Türkçe, kısa)

- Başlık: `<cihaz adı>: <kural adı>`; ör. "Redmi Note 13 Pro: Pil azaldı".
- Metin: değer ve bağlam; ör. "%18 kaldı, şarjda değil." / "Disk %91 dolu, 41 GB boş." / "İşlemci 3 dakikadır %94." / "Pil 44,2°C." / "15 dakikadır görülmedi."
- Bildirime tıklayınca uygulama açılır (Mac: panel, Android: ilgili sekme).

## Ayarlar arayüzü

- Mac: Ayarlar'a **Bildirimler** sekmesi (mevcut hap sekmelere eklenir). Üstte "Bildirimlere izin ver" durumu (izin yoksa Sistem Ayarları bağlantısı). Sonra iki bölüm: **Bu Mac** ve **Telefon**; her kural bir satır: SF Symbol + ad + gri açıklama (eşik metinle: "%20 ve altı"), sağda anahtar; açıkken satırın altında eşik için `Stepper` ya da kaydırıcı. En altta "Deneme bildirimi gönder".
- Android: Ayarlar'da **Uyarılar** bölümü, aynı yapı: **Telefon** ve **Mac** grupları, anahtar + eşik kaydırıcı; "Deneme bildirimi gönder". Ayrı bildirim kanalı `uyarilar` (yüksek önem), Mac kartı kanalından ayrı.

## Saklama anahtarları

`alert.<id>.<konu>.on` (bool), `alert.<id>.<konu>.esik` (int), `alert.<id>.<konu>.sureDk` (int), `alert.<id>.<konu>.son` (son bildirim epoch sn), `alert.<id>.<konu>.aktif` (koşul şu an doğru mu, histerezis için). `<konu>`: `mac` ya da `telefon`.
