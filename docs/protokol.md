# Mac <-> Android kanali (Nabiz, v1)

Swift (Mac) ve Kotlin (Android) tarafinin birebir uygulayacagi TEK KAYNAK.
ORBIO'nun (`~/Library/bt-ekosistem/docs/telefon-kanali.md`) cihazda calistigi dogrulanmis kanalidir; bolum 2-6 ve 8 oradan aynen alindi.
Kripto sabitleri (`"BTEKO1"`, `"btekosistem/v1"`) bilerek DEGISTIRILMEDI: bolum 8'deki test vektorleri gecerli kalsin diye. Servis tipi farkli oldugu icin iki uygulama karismaz.
Referans kod (yalniz okunur, sadelestirerek tasinabilir): Swift `~/Library/bt-ekosistem/Sources/EkosistemCore/Peer{Session,Crypto,Framing,Message}.swift`, Kotlin `~/Library/bt-ekosistem/Android/app/src/main/kotlin/com/btekosistem/android/peer/Peer{Session,Crypto,Framing,Json,Message,Store}.kt`, `MacDiscovery.kt`, `ReconnectBackoff.kt`.

## 1. Roller ve kesif

- **Mac = sunucu** (`rol: "mac"`): TCP'de dinler, Bonjour ile yayin yapar. **Telefon = istemci** (`rol: "telefon"`): kesfeder, baglanir.
- Servis tipi: `_nabiz._tcp` (Android NSD: `_nabiz._tcp.`). Port sistemden.
- TXT: `ad`, `surum` (`1`), `id` (kalici rastgele UUID).
- Mac ayni anda tek telefonla oturum tutar. Eslesmis telefon disindan gelen ikinci baglanti reddedilir.
- Mac sabit portta dinler: 47821 (doluysa sistemin verdigi port; Bonjour ikisini de duyurur).
- **Uzak baglanti** (ev disi): Tailscale benzeri ozel ag uzerinden. Telefon ayarinda "Uzak adres" (`host` ya da `host:port`, varsayilan port 47821). Telefon once NSD dener; bulamazsa ve Mac pinliyse uzak adrese baglanir. Ilk eslesme (SAS) YALNIZ yerel agda: pinsiz Mac'e uzak adresten baglanilmaz.
- Bluetooth yedek kanali yok (v1).

## 2. Tasima

TCP. Her cerceve: `uzunluk (4 bayt, big-endian, imzasiz) || yuk`. Yuk uzunlugu 1..1 048 576 bayt; 0 veya fazlasi protokol hatasidir, baglanti kapatilir. TCP akisi parcali gelebilir: alici tam cerceve olana dek tamponlar.

- El sikisma cerceveleri (bolum 3) duz JSON'dur.
- El sikismadan sonra her cerceve yuku bolum 5'teki sifreli pakettir.

## 3. El sikisma (duz metin)

Baglanti kurulunca iki taraf da hemen birer `hs` cercevesi gonderir (UTF-8 JSON):

```json
{"t":"hs","v":1,"rol":"mac","pub":"<base64>","nonce":"<base64>","ad":"MacBook"}
```

- `v`: protokol surumu (1). Farkliysa kapat.
- `rol`: `mac` veya `telefon`. Iki taraf ayni rolde ise kapat.
- `pub`: uzun omurlu P-256 acik anahtar, **X9.63 sikistirilmamis nokta, 65 bayt** (`04 || X(32) || Y(32)`), standart base64 (dolgulu).
- `nonce`: 16 rastgele bayt, standart base64.
- `ad`: gorunen ad.
- Alinan `hs` gecersizse (JSON, uzunluklar, gecersiz egri noktasi) kapat.

## 4. Anahtar turetme

Her cihazin kalici bir P-256 kimlik anahtari vardir (Mac: `~/Library/Application Support/Nabiz/` altinda 0600 dosya, Keychain KULLANILMAZ [ORBIO'da donma yapti]; Android: Keystore ile sarili sifreli depo; ham ozel anahtar 32 bayt). Oturum anahtari bu kimlik anahtarlariyla ECDH'dan turetilir (ileri gizlilik yok; nonce'lar her oturumu ayirir).

1. `secret` = ECDH(kendi ozel, karsi acik) -> **32 bayt x koordinati** (CryptoKit `sharedSecretFromKeyAgreement`; Android `KeyAgreement("ECDH").generateSecret()`).
2. `transcript` = `"BTEKO1"` (ASCII, 6 bayt) `|| macPub(65) || telefonPub(65) || macNonce(16) || telefonNonce(16)` (Mac ve telefon sirasi sabit, kimin gonderdigine gore degil role gore).
3. `salt` = SHA-256(`transcript`) (32 bayt).
4. `okm` = HKDF-SHA256(ikm = `secret`, salt = `salt`, info = `"btekosistem/v1"` ASCII, L = 68).
5. Bolme: `okm[0..32)` = mac->telefon AES anahtari; `okm[32..64)` = telefon->mac AES anahtari; `okm[64..68)` = SAS ham degeri.
6. **SAS** = `uint32_big_endian(okm[64..68)) mod 1 000 000`, 6 haneye soldan `0` ile doldurulmus ondalik metin.

Android'de HKDF elle (RFC 5869) yapilir: `PRK = HMAC-SHA256(key=salt, msg=ikm)`; `T(i) = HMAC-SHA256(key=PRK, msg=T(i-1) || info || i)` (i tek bayt, 1'den; T(0) bos); `okm` = T(1)||T(2)||T(3) ilk 68 bayt.

## 5. Sifreli paket

AES-256-GCM. Her yonun kendi anahtari ve sayaci vardir (mac gonderirken `mac->telefon` anahtari, telefon gonderirken `telefon->mac`).

- Gonderen sayac 1'den baslar, her pakette 1 artar (uint64).
- `sayac8` = sayac, 8 bayt big-endian. `nonce` (12 bayt) = `00 00 00 00 || sayac8`. AAD = `sayac8`. Etiket 16 bayt.
- Paket = `sayac8 || sifreliMetin || etiket(16)`; en az 24 bayt. Bu paket cerceve yukudur.
- Alici: once sayaci okur; **sayac <= son kabul edilen sayac ise tekrardir, reddedilir**. Etiket dogrulanirsa son sayaci ilerletir. Dogrulanamayan paket sayaci ilerletmez.
- Etiket dogrulama hatasi, tekrar, kisa paket: **olumcul**, baglanti kapatilir.
- Yazilan acik metin: tek bir JSON mesaji (bolum 7).

## 6. Eslesme (ilk baglanti) ve pin

- Karsi tarafin acik anahtari daha once **sabitlenmemisse** (ilk eslesme): anahtarlar turetilir, iki ekranda ayni 6 haneli SAS gosterilir, kullanici ikisinde de ayni oldugunu onaylar (MITM korumasi: araya giren iki tarafla farkli anahtar kullanacagindan kodlar farkli cikar). Red olursa baglanti kapatilir.
- Onayda: uygulama karsi `pub` degerini kalici saklar (pin: Mac `~/Library/Application Support/Nabiz/` altinda 0600 dosya, telefon sifreli depo / Keystore ile sarili) ve her taraf sifreli `hello` mesajini gonderir. SAS onaylanmadan gelen sifreli mesajlar bekletilir; onaydan sonra islenir, red halinde atilir.
- Anahtar **sabitlenmisse**: `hs.pub` sabitlenen anahtara esit olmali, degilse baglanti kapatilir (kullaniciya "eslesme anahtari degisti" uyarisi; yalniz kullanici eslesmeyi silip yeniden eslestirerek asilabilir). Sabitlenmis anahtarda SAS gosterilmez; oturum dogrudan kurulur. Anahtar sahipligi kanitini, ilk sifreli mesajin dogrulanmasi verir (ozel anahtari olmayan dogru anahtari turetemez).
- Eslemeyi silmek: iki taraf da pini siler.

## 7. Mesajlar

Her mesaj tek JSON nesnesi, UTF-8: `{"t":"<tip>","id":n,...}`. `id` istege bagli; yanit istegin `id`sini tasir. Bilinmeyen ek alanlar yok sayilir. Bozuk JSON olumcul; bilinmeyen `t` olumcul degil, `error` {kod:"bilinmeyen_tip"} ile yanitlanir. `null` alan yazilmaz.

| `t` | Yon | Alanlar |
|---|---|---|
| `hello` | iki yon | `ad`, `surum` (uygulama), `protokol` (1), `cihazId`, `platform` (`mac`/`android`), `model` (opsiyonel, or. "MacBook Air (M4)", "Redmi Note 13 Pro") |
| `ping` / `pong` | iki yon | yok |
| `stats` | iki yon | `snap`: asagidaki Snapshot nesnesi |
| `sub` | iki yon | `aralikSn` (tam sayi, 1..60): karsi taraf `stats`i bu siklikta yollasin |
| `cmd` | tel->mac | `eylem`: `yenile` / `kilitle` / `uyut` / `uyandir` (ekrani uyandirir; Mac uyaniksa ve ekran kapaliysa) |
| `mac.state` | mac->tel | `kilitli` (bool), `ekranKapali` (bool), `uykuyaGidiyor` (bool, yalniz uyumadan hemen once true) |
| `cmd.result` | mac->tel | `eylem`, `sonuc`: `tamam` / `kapali` (ayarlardan kapatilmis) / `hata` |
| `error` | iki yon | `kod`, `mesaj` |

**Snapshot** (Swift `NabizCore/Snapshot.swift` ile birebir; Kotlin ayni adlarla). Tum alanlar opsiyonel (okunamayan yazilmaz), `ts` zorunlu:

```
ts: epoch sn (Int)
cpu:     { total: 0-100, cores: [0-100], perfCores?: Int, effCores?: Int }      (Android YAZMAZ; cores sirasi: once effCores adet E, sonra perfCores adet P)
mem:     { used: bayt, total: bayt, pressure?: "normal"|"warn"|"critical" }
disk:    { used: bayt, total: bayt }
battery: { level: 0-100, charging: Bool, health?: %, cycles?: Int, minutes?: dk, temp?: santigrat (Double, Android) }
net:     { up: B/s, down: B/s }
gpu:     0-100        (yalniz Mac)
uptime:  sn
thermal?: "normal"|"warn"|"critical"   (Android PowerManager termal durumu; Mac yazmaz)
```

Kurallar:
- Oturum kurulunca iki taraf `hello`, ardindan `sub` (kendi istedigi aralik) ve hemen bir `stats` gonderir.
- Varsayilan aralik: telefon ekrani acik ya da Mac paneli acikken 2 sn; aksi halde 10 sn. Kosul degisince yeni `sub` yollanir.
- `cmd` eylemleri Mac Ayarlar'da tek anahtarla (varsayilan ACIK: yenile; KAPALI: kilitle, uyut) kapatilabilir; kapaliysa `cmd.result` `kapali`.
- `mac.state`: oturum kurulunca bir kez, sonra her degisimde. Mac kilit durumunu `com.apple.screenIsLocked` / `screenIsUnlocked` dagitik bildirimlerinden, ekrani `NSWorkspace.screensDidSleep/WakeNotification`dan, uykuyu `willSleepNotification`dan okur; uyumadan once `uykuyaGidiyor:true` gonderir (bildirim gec kalabilir, telefon ayrica baglanti kopunca "son gorulme" gosterir).
- Telefonda butonlar `mac.state`e gore: kilitliyse "Kilitle" pasif; ekran kapaliysa "Uyandir" gorunur; `uykuyaGidiyor` sonrasi kopus "Mac uykuda" olarak gosterilir.
- Kilit acma YOK (macOS ucuncu parti uygulamaya izin vermez; parola saklamak guvensiz).
- `ping` en az 15 sn'de bir; 45 sn mesaj gelmezse oturum olu, telefon yeniden baglanir (geri cekilme 2/5/15/30 sn).
- **Gecikme (2026-11-18):** `ping` artik `id` tasir (gonderene ozel artan sayi); karsi taraf ayni `id` ile `pong` doner. Gonderen, monoton saatle gonderim-yanit farkini **RTT (ms)** olarak olcer; son 5 olcumun ortancasi arayuzde "Gecikme" olarak gosterilir. Oturum kurulunca hemen bir `ping` atilir. `id`siz eski `pong` yok sayilir (olcum yapilmaz). Kablo uzerinde yeni alan yok, eski surumlerle uyumlu.
- **Surum uyumsuzlugu (2026-11-18):** `hs.v` farkliysa baglanti yine kapatilir ama once iki taraf da kullaniciya acik bir neden gosterir: Mac "Telefondaki Nabiz farkli protokol surumunde (v{X}). Iki uygulamayi da guncelleyin."; Android `LinkReason.VERSION` -> "Mac'teki Nabiz farkli surumde (v{X}). Iki uygulamayi da guncelleyin." Bu durumda telefon hizli yeniden deneme dongusune girmez (en uzun geri cekilme). `hello.protokol` da `hs.v` ile karsilastirilir.
- **Ortak ornekler:** `docs/fixtures/messages.json` (mesajlar) ve `docs/fixtures/vectors.json` (bolum 8). Iki platformun testleri bu dosyalari OKUR; bu dosyalar ile bu belge tek kaynaktir.

## 8. Test vektorleri

Iki platform bu degerleri uretebildigini dogrulamalidir. Hex kucuk harf.

**HKDF (RFC 5869 test 1):** ikm = `0b` x22, salt = `00..0c`, info = `f0..f9`, L=42 ->
`3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865`

**Anahtar turetme (sabit girdiler):**

- mac ozel anahtari (ham 32 bayt): `01 02 .. 20` (1'den 32'ye)
- telefon ozel anahtari: `21 22 .. 40` (33'ten 64'e)
- macNonce: `a0 a1 .. af`; telefonNonce: `b0 b1 .. bf`
- macPub: `04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354`
- telefonPub: `041f140146bfb1b251f84f4ddbe0d4cdcfd77afd984a9520e35794021f8312bb9eec995a08b1fa7704df3dcc0b50a9665263fb7711f95f9f8a449c5096e47c892b`
- ECDH secret: `4fe243908f378aa1c2a69538822e6ed908c3225d8692575507c649901245150a`
- salt (transcript SHA-256): `ba69f2c2355561d031c3e7fe8c06b0c274daab2afb207059ab9334abd561879a`
- mac->telefon anahtari: `3e7994371738fd367f8393c81893a0371df27a71ed52fdd4142ec49917eccef0`
- telefon->mac anahtari: `cbe20cf9b684bdb2a428ae219e708ce69a45856684940b59a7a0165e3df6aaf8`
- SAS: `538801`

(Not: 1..32 ve 33..64 ham degerleri gecerli P-256 skalerleridir. Android'de ham skalerden anahtar uretmek icin `ECPrivateKeySpec(BigInteger(1, bytes), secp256r1)` kullanin; X9.63 acik anahtari `04 || X || Y` olarak 32 bayta sola sifir doldurarak seri hale getirin.)

**AES-256-GCM:** anahtar = `00 01 .. 1f`, sayac = 1, acik metin = `{"id":1,"t":"ping"}` (UTF-8, 19 bayt) -> paket:
`00000000000000016ef4d69866ce01322c5a7303ced6539972bd6149d15d86aae12692f305fb8fdc1a15c0`
(8 bayt sayac + 19 bayt sifreli metin + 16 bayt etiket.)

**Cerceve:** yuk `01 02 03` -> `00 00 00 03 01 02 03`.

**JSON ornekleri** (alan sirasi onemsiz, referans kodlayici anahtarlari siralar):
`{"id":2,"numara":"555","t":"call.dial"}`, `{"durum":"bosta","t":"call.state"}`,
`{"aramaGecmisi":false,"cagriYonetimi":false,"kisiler":false,"t":"perm.state"}`.

## 9. Uygulama notlari

- Swift: aga bagli olmayan `PeerSession` durum makinesi + `PeerCrypto`/`PeerCipher`/`PeerFrameBuffer`/`PeerCodec` NabizCore'da (birim testli, bolum 8 vektorleri). Ag kabugu (NWListener + Bonjour) Nabiz hedefinde.
- Kotlin: ayni durum makinesi bire bir, ayni vektorlerle JVM testi.
- Zaman asimi: el sikisma 10 sn, SAS onayi 60 sn.

## 10. Telefon: aramalar, kisiler, bildirimler (2026-11-19)

Arama ve kisi mesajlari ORBIO'dan (`~/Library/bt-ekosistem/docs/telefon-kanali.md` bolum 7 + `docs/kisiler-protokolu.md`) **aynen** alindi; bildirim mesajlari yeni (ORBIO'da yalniz Figma M7 tasarimi var). Protokol surumu 1 kalir: eski surum bilinmeyen `t` icin `error` {kod:"bilinmeyen_tip"} doner, olumcul degil.

**Izinler** (telefonda Ayarlar > "Mac ile paylas" anahtarlari, **hepsi varsayilan KAPALI**): `bildirimler` (Bildirim erisimi, sistem ayari), `cagriYonetimi` (READ_PHONE_STATE + ANSWER_PHONE_CALLS + CALL_PHONE), `kisiler` (READ_CONTACTS), `aramaGecmisi` (READ_CALL_LOG). Anahtar acik VE sistem izni verilmisse `true`. Izin yokken gelen istek islenmez; ayni `id` ile `error` {kod:"izin_yok", mesaj:"<izin anahtari>"}. Mac izni kapali ozelligi gostermez. Mac bu verileri diske YAZMAZ; kopunca ve izin kapaninca bellekten siler.

| `t` | Yon | Alanlar |
|---|---|---|
| `perm.state` | tel->mac | `bildirimler`, `cagriYonetimi`, `kisiler`, `aramaGecmisi` (bool) |
| `call.state` | tel->mac | `durum`: `bosta`/`caliyor`/`acik`/`araniyor`; `yon`: `gelen`/`giden` (bostayken yok); `numara?`, `kisiAdi?`, `sureSn?` |
| `call.answer` / `call.reject` / `call.hangup` | mac->tel | yok |
| `call.dial` | mac->tel | `numara` |
| `contacts.sync` | mac->tel | `ofset`, `adet?` (varsayilan 40, en cok 100) |
| `contacts.page` | tel->mac | `ofset`, `toplam`, `son`, `kisiler`: `[{kid, ad, numaralar:[{no, tur: cep/ev/is/diger}], favori, gruplar:[metin], foto?}]` |
| `contacts.changed` | tel->mac | yok |
| `calllog.sync` | mac->tel | `ofset`, `adet?` (varsayilan 100, en cok 200) |
| `calllog.page` | tel->mac | `ofset`, `toplam`, `son`, `kayitlar`: `[{numara, kisiAdi?, yon: gelen/giden/cevapsiz, zaman (epoch sn), sureSn}]` |
| `calllog.changed` | tel->mac | yok |
| `notif.list` | tel->mac | `bildirimler`: `[Bildirim]` (tum guncel liste, en yeni once, en cok 50) |
| `notif.posted` | tel->mac | `bildirim`: `Bildirim` (yeni ya da guncellenen; ayni `anahtar` yerini alir) |
| `notif.removed` | tel->mac | `anahtar` |
| `notif.dismiss` | mac->tel | `anahtar` (telefonda kapatir; sonra telefon `notif.removed` yollar) |
| `notif.clear` | mac->tel | yok (kapatilabilir tum bildirimleri kapatir) |
| `notif.reply` | mac->tel | `anahtar`, `metin` (bildirimin RemoteInput yanit eylemiyle gonderilir) |
| `notif.result` | tel->mac | `anahtar`, `sonuc`: `tamam`/`bulunamadi`/`desteklenmiyor`/`hata` (yalniz `notif.reply` icin, istek `id`siyle) |

**Bildirim** nesnesi: `anahtar` (StatusBarNotification.key), `paket`, `uygulama` (gorunen ad), `baslik?`, `metin?`, `zaman` (epoch sn), `yanitlanabilir` (bool), `kapatilabilir` (bool), `ikon?` (uygulama ikonu, en cok 64 px PNG, standart base64, en cok 6 KB; Mac pakete gore onbellekte tutar, telefon ayni paketi oturumda bir kez ikonlu yollayabilir).

Kurallar:
- Oturum kurulunca telefon `hello`dan sonra `perm.state`, `call.state` (bosta degilse) ve `bildirimler` acikse `notif.list` yollar. Izin degisince `perm.state` (ve bildirim acildiysa `notif.list`) yeniden.
- Telefon su bildirimleri YOLLAMAZ: kendi paketi, `FLAG_ONGOING_EVENT`/`isOngoing`, grup ozeti (`FLAG_GROUP_SUMMARY`), `CATEGORY_CALL` (arama kendi kanalinda), `CATEGORY_TRANSPORT` (medya), baslik ve metni bos olanlar. Metin en cok 400 karakter (kesilir).
- Ayni `anahtar` saniyede 1'den sik `notif.posted` olmaz (son hali gonderilir).
- `call.state` sureSn yalniz `acik`ta; Mac sayaci kendisi yurutur.
- Mac'te gosterilen macOS banner'lari sistemin Bildirim Merkezi'nde kalir (macOS kendi diskine yazar; uygulama yazmaz). Mac kilitli ya da ekran kapaliyken banner yalniz uygulama adini gosterir, icerik yok.
- Sayfa/foto kurallari ORBIO `kisiler-protokolu.md` ile ayni: foto en cok 96 px JPEG 8 KB; yalniz numarali kisiler; Mac sira disi `ofset`i yoksayar, `ofset 0` listeyi sifirlar; son arama en cok 300 kayit.
- Ornekler `docs/fixtures/messages.json` icinde `perm-state`, `call-*`, `contacts-*`, `calllog-*`, `notif-*` adlariyla.
