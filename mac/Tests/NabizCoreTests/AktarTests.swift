import Testing
import Foundation
import CryptoKit
@testable import NabizCore

// Aktar (docs/protokol.md bolum 13): anahtar vektoru, cerceve, devam ofseti, SHA uyumsuzlugu, uctan uca akis.

private func vectorsURL(file: String = #filePath) -> URL {
    var url = URL(fileURLWithPath: file)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("docs/fixtures/vectors.json")
}

private func aktarVector() throws -> [String: Any] {
    let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: vectorsURL())) as? [String: Any])
    return try #require(root["aktar"] as? [String: Any])
}

private func unhex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

private func keyBytes(_ k: SymmetricKey) -> Data { k.withUnsafeBytes { Data($0) } }

private func tempDir() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("nabiz-aktar-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private func sha(_ d: Data) -> String { AktarHex.string(SHA256.hash(data: d)) }

// MARK: Anahtar vektoru

@Test func aktarAnahtarVektoru() throws {
    let v = try aktarVector()
    let aid = try #require(v["aid"] as? String)
    #expect(AktarCrypto.salt(aid: aid) == unhex(try #require(v["salt"] as? String)))
    let keys = try AktarCrypto.deriveKeys(sessionKeyMaterial: unhex(try #require(v["ikm"] as? String)), aid: aid)
    #expect(keyBytes(keys.senderToReceiver) == unhex(try #require(v["senderToReceiver"] as? String)))
    #expect(keyBytes(keys.receiverToSender) == unhex(try #require(v["receiverToSender"] as? String)))
}

@Test func aktarVeriPaketiVektoru() throws {
    let v = try aktarVector()
    let keys = try AktarCrypto.deriveKeys(sessionKeyMaterial: unhex(try #require(v["ikm"] as? String)),
                                          aid: try #require(v["aid"] as? String))
    let plain = unhex(try #require(v["plaintext"] as? String))
    let expectedPacket = unhex(try #require(v["packet"] as? String))
    // Cerceve: fid / ofset / bayt acik metinle birebir.
    let enc = try AktarFraming.encodeData(fid: try #require(v["fid"] as? Int), ofset: UInt64(try #require(v["ofset"] as? Int)),
                                          bayt: unhex(try #require(v["bayt"] as? String)))
    #expect(enc == plain)
    var gonderen = AktarCipher(role: .gonderen, keys: keys)
    #expect(try gonderen.seal(plain) == expectedPacket)
    var alici = AktarCipher(role: .alici, keys: keys)
    #expect(try alici.open(expectedPacket) == plain)
    // Ayni paket ikinci kez: tekrar reddi.
    #expect(throws: PeerCryptoError.tekrar) { try alici.open(expectedPacket) }
}

@Test func aktarYonluAnahtarlarAyriDir() throws {
    let km = Data((0..<64).map { UInt8($0) })
    let a = try AktarCrypto.deriveKeys(sessionKeyMaterial: km, aid: "a1")
    let b = try AktarCrypto.deriveKeys(sessionKeyMaterial: km, aid: "a2")
    #expect(keyBytes(a.senderToReceiver) != keyBytes(a.receiverToSender))
    #expect(keyBytes(a.senderToReceiver) != keyBytes(b.senderToReceiver))   // aid'e ozel
    #expect(throws: PeerCryptoError.gecersizAnahtar) { try AktarCrypto.deriveKeys(sessionKeyMaterial: Data(count: 10), aid: "x") }
}

@Test func aktarAliciGonderenYonuYanlisAnahtarlaAcilmaz() throws {
    let keys = try AktarCrypto.deriveKeys(sessionKeyMaterial: Data(repeating: 7, count: 64), aid: "z")
    var g = AktarCipher(role: .gonderen, keys: keys)
    var g2 = AktarCipher(role: .gonderen, keys: keys)
    let p = try g.seal(Data("merhaba".utf8))
    #expect(throws: PeerCryptoError.kimlikDogrulama) { try g2.open(p) }   // gonderen kendi paketini acamaz
}

// MARK: Cerceve

@Test func aktarVeriCercevesiKodlaCoz() throws {
    let payload = Data((0..<1000).map { UInt8($0 & 0xFF) })
    let enc = try AktarFraming.encodeData(fid: 513, ofset: 0x0102030405060708, bayt: payload)
    #expect(enc.count == AktarFraming.veriBasligi + payload.count)
    #expect(Array(enc.prefix(11)) == [0x02, 0x02, 0x01, 1, 2, 3, 4, 5, 6, 7, 8])
    #expect(try AktarFraming.decode(enc) == .veri(fid: 513, ofset: 0x0102030405060708, bayt: payload))
}

@Test func aktarKontrolCercevesiKodlaCoz() throws {
    let json = Data(#"{"t":"devam","ofsetler":{}}"#.utf8)
    let enc = AktarFraming.encodeControl(json)
    #expect(enc.first == 0x01)
    #expect(try AktarFraming.decode(enc) == .kontrol(json))
}

@Test func aktarCerceveSiniriVeHatalar() throws {
    let tam = Data(count: AktarFraming.maxVeri)
    let enc = try AktarFraming.encodeData(fid: 0, ofset: 0, bayt: tam)
    guard case .veri(_, _, let b) = try AktarFraming.decode(enc) else { Issue.record("veri bekleniyordu"); return }
    #expect(b.count == AktarFraming.maxVeri)
    #expect(throws: AktarFrameError.cokBuyukVeri(AktarFraming.maxVeri + 1)) {
        try AktarFraming.encodeData(fid: 0, ofset: 0, bayt: Data(count: AktarFraming.maxVeri + 1))
    }
    #expect(throws: AktarFrameError.gecersizFid(70000)) { try AktarFraming.encodeData(fid: 70000, ofset: 0, bayt: Data()) }
    #expect(throws: AktarFrameError.bos) { try AktarFraming.decode(Data()) }
    #expect(throws: AktarFrameError.bilinmeyenTur(0x09)) { try AktarFraming.decode(Data([0x09, 1])) }
    #expect(throws: AktarFrameError.kisaVeri) { try AktarFraming.decode(Data([0x02, 0, 1, 2])) }
}

@Test func aktarDisCerceveParcaliGelenBaytlariBirlestirir() throws {
    var buf = PeerFrameBuffer()
    let a = try PeerFrame.encode(Data(repeating: 1, count: 300_000))
    let b = try PeerFrame.encode(Data(repeating: 2, count: 5))
    let all = a + b
    var frames: [Data] = []
    var i = 0
    while i < all.count {   // 70 000 baytlik parcalarla
        let j = min(all.count, i + 70_000)
        frames += try buf.append(all[i..<j])
        i = j
    }
    #expect(frames.count == 2)
    #expect(frames[0] == Data(repeating: 1, count: 300_000))
    #expect(frames[1] == Data(repeating: 2, count: 5))
    #expect(buf.pendingByteCount == 0)
}

@Test func aktarKontrolMesajlariKodlaCoz() throws {
    for k in [AktarKontrol.devam(ofsetler: [0: 10, 3: 99]), .devam(ofsetler: [:]),
              .dosyaSon(fid: 2, sha256: "ab12"), .dosyaHata(fid: 5)] {
        #expect(try AktarKontrolCodec.decode(try AktarKontrolCodec.encode(k)) == k)
    }
    let devam = try AktarKontrolCodec.decode(Data(#"{"t":"devam","ofsetler":{"1":42}}"#.utf8))
    #expect(devam == .devam(ofsetler: [1: 42]))
    #expect(throws: PeerMessageError.bilinmeyenTip("yeni.mesaj")) { try AktarKontrolCodec.decode(Data(#"{"t":"yeni.mesaj"}"#.utf8)) }
}

@Test func aktarBaglanCercevesi() throws {
    let framed = try AktarBaglan.encode(aid: "6c1f")
    var buf = PeerFrameBuffer()
    let frames = try buf.append(framed)
    #expect(frames.count == 1)
    #expect(AktarBaglan.decode(frame: frames[0]) == "6c1f")
    #expect(AktarBaglan.decode(frame: Data(#"{"t":"baska","aid":"x"}"#.utf8)) == nil)
    #expect(AktarBaglan.decode(frame: Data("bozuk".utf8)) == nil)
}

// MARK: Ad, yer, devam ofseti

@Test func aktarAdTemizlemeVeBenzersiz() {
    #expect(AktarAd.temizle("../../etc/passwd") == "passwd")
    #expect(AktarAd.temizle("..") == "dosya")
    #expect(AktarAd.temizle(".gizli") == "gizli")
    #expect(AktarAd.temizle("a:b.jpg") == "a-b.jpg")
    #expect(AktarAd.temizle(String(repeating: "x", count: 400) + ".png").utf8.count <= AktarAd.enFazlaBayt)
    #expect(AktarAd.benzersiz("foto.jpg") { _ in false } == "foto.jpg")
    #expect(AktarAd.benzersiz("foto.jpg") { ["foto.jpg", "foto (2).jpg"].contains($0) } == "foto (3).jpg")
    #expect(AktarAd.benzersiz("not") { $0 == "not" } == "not (2)")
}

@Test func aktarDevamOfseti() {
    let d = [AktarDosya(fid: 0, ad: "a", boyut: 100), AktarDosya(fid: 1, ad: "b", boyut: 50),
             AktarDosya(fid: 2, ad: "c", boyut: 10), AktarDosya(fid: 3, ad: "d", boyut: 0)]
    let sizes: [Int: UInt64] = [0: 40, 1: 80 /* boyuttan buyuk: gecersiz */, 3: 0]
    let o = AktarDevam.ofsetler(dosyalar: d) { sizes[$0] }
    #expect(o == [0: 40])
    #expect(AktarYer.yeterli(gereken: 100, bos: 99) == false)
    #expect(AktarYer.yeterli(gereken: 100, bos: 100))
    #expect(AktarYer.yeterli(gereken: 100, bos: nil))
}

// MARK: Dosya yazici / okuyucu (uctan uca)

private func yaziciAc(dir: URL, aid: String, ad: String, data: Data, degisme: Int64?, devam: UInt64) throws -> AktarDosyaYazici {
    try AktarDosyaYazici(partURL: dir.appendingPathComponent(AktarAd.partAdi(aid: aid, fid: 0, ad: ad)), ad: ad,
                         boyut: Int64(data.count), degisme: degisme, fid: 0, devamEt: devam)
}

@Test func aktarDosyaBaytBaytAyniVeTarihUygulanir() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data((0..<1_300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    let src = dir.appendingPathComponent("kaynak.bin")
    try data.write(to: src)
    let hedef = dir.appendingPathComponent("hedef"); try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true)

    let r = try AktarDosyaOkuyucu(url: src, beklenenBoyut: Int64(data.count))
    try r.basla(ofset: 0)
    let w = try yaziciAc(dir: hedef, aid: "aid-1", ad: "kaynak.bin", data: data, degisme: 1_700_000_000, devam: 0)
    while let p = try r.sonraki(en: AktarFraming.maxVeri) { try w.yaz(ofset: p.ofset, bayt: p.bayt) }
    let hash = r.sha256
    r.kapat()
    #expect(hash == sha(data))
    guard case .tamam(let url) = try w.bitir(sha256: hash, hedefKlasor: hedef) else { Issue.record("tamam bekleniyordu"); return }
    #expect(try Data(contentsOf: url) == data)
    let mod = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    #expect(Int(mod.timeIntervalSince1970) == 1_700_000_000)
    // Ayni ad ikinci kez: " (2)".
    let w2 = try yaziciAc(dir: hedef, aid: "aid-2", ad: "kaynak.bin", data: data, degisme: nil, devam: 0)
    try w2.yaz(ofset: 0, bayt: data)
    guard case .tamam(let url2) = try w2.bitir(sha256: sha(data), hedefKlasor: hedef) else { Issue.record("tamam bekleniyordu"); return }
    #expect(url2.lastPathComponent == "kaynak (2).bin")
}

@Test func aktarYarimDosyaKaldigiYerdenSurer() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data((0..<400_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) })
    let src = dir.appendingPathComponent("k.bin"); try data.write(to: src)
    let hedef = dir.appendingPathComponent("h"); try FileManager.default.createDirectory(at: hedef, withIntermediateDirectories: true)

    // Ilk baglanti: 150 000 bayt yazilir, kopar (silmeden kapat).
    let w1 = try yaziciAc(dir: hedef, aid: "devam", ad: "k.bin", data: data, degisme: nil, devam: 0)
    try w1.yaz(ofset: 0, bayt: data.prefix(150_000))
    w1.kapat(sil: false)

    // Alici `devam` ofsetini diskten bulur.
    let dosyalar = [AktarDosya(fid: 0, ad: "k.bin", boyut: Int64(data.count))]
    let part = hedef.appendingPathComponent(AktarAd.partAdi(aid: "devam", fid: 0, ad: "k.bin"))
    let o = AktarDevam.ofsetler(dosyalar: dosyalar) { _ in
        (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.uint64Value
    }
    #expect(o == [0: 150_000])

    // Ikinci baglanti: gonderen ofsetten surer; SHA tum dosyayi kapsar.
    let r = try AktarDosyaOkuyucu(url: src, beklenenBoyut: Int64(data.count))
    try r.basla(ofset: 150_000)
    #expect(r.konum == 150_000)
    let w2 = try yaziciAc(dir: hedef, aid: "devam", ad: "k.bin", data: data, degisme: nil, devam: 150_000)
    #expect(w2.yazilan == 150_000)
    // Ofset uyusmazligi reddedilir.
    #expect(throws: AktarYazmaHatasi.ofsetUyusmuyor(beklenen: 150_000, gelen: 0)) { try w2.yaz(ofset: 0, bayt: Data([1])) }
    while let p = try r.sonraki(en: 100_000) { try w2.yaz(ofset: p.ofset, bayt: p.bayt) }
    #expect(r.sha256 == w2.sha256)
    guard case .tamam(let url) = try w2.bitir(sha256: r.sha256, hedefKlasor: hedef) else { Issue.record("tamam bekleniyordu"); return }
    #expect(try Data(contentsOf: url) == data)
    r.kapat()
}

@Test func aktarShaUyumsuzluguDosyayiSilerVeBastanIster() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data(repeating: 0xAB, count: 70_000)
    let w = try yaziciAc(dir: dir, aid: "sha", ad: "x.dat", data: data, degisme: nil, devam: 0)
    try w.yaz(ofset: 0, bayt: data)
    let part = w.partURL
    #expect(FileManager.default.fileExists(atPath: part.path))
    #expect(try w.bitir(sha256: String(repeating: "0", count: 64), hedefKlasor: dir) == .shaUyusmuyor)
    #expect(!FileManager.default.fileExists(atPath: part.path))
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("x.dat").path))
}

@Test func aktarEksikDosyaBitmez() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let data = Data(repeating: 1, count: 100)
    let w = try yaziciAc(dir: dir, aid: "e", ad: "e.bin", data: data, degisme: nil, devam: 0)
    try w.yaz(ofset: 0, bayt: data.prefix(50))
    #expect(try w.bitir(sha256: sha(data), hedefKlasor: dir) == .eksik)
    #expect(throws: AktarYazmaHatasi.tasma) { try w.yaz(ofset: 50, bayt: Data(count: 51)) }
    w.kapat(sil: true)
}

@Test func aktarOkuyucuDegisenDosyayiYakalar() throws {
    let dir = try tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
    let src = dir.appendingPathComponent("d.bin"); try Data(count: 100).write(to: src)
    #expect(throws: AktarOkumaHatasi.degisti) { try AktarDosyaOkuyucu(url: src, beklenenBoyut: 99) }
}

// MARK: Mesajlar

@Test func aktarTeklifGecerliligi() {
    let ok = AktarTeklif(aid: "a", dosyalar: [AktarDosya(fid: 0, ad: "x", boyut: 5), AktarDosya(fid: 1, ad: "y", boyut: 7)], toplam: 12)
    #expect(ok.gecerli)
    #expect(ok.gercekToplam == 12)
    #expect(!AktarTeklif(aid: "a", dosyalar: [AktarDosya(fid: 1, ad: "x", boyut: 5)], toplam: 5).gecerli)   // fid 0'dan degil
    #expect(!AktarTeklif(aid: "a", dosyalar: [], toplam: 0).gecerli)
    #expect(!AktarTeklif(aid: "", dosyalar: ok.dosyalar, toplam: 12).gecerli)
    #expect(!AktarTeklif(aid: "a", dosyalar: [AktarDosya(fid: 0, ad: "x", boyut: -1)], toplam: 0).gecerli)
}
