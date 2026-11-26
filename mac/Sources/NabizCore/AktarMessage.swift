import Foundation

// Aktar mesajlari (docs/protokol.md bolum 13).
// Kontrol kanali (aktar.*): PeerMessage icinde. Veri baglantisi kontrolu (devam, dosya.son, dosya.hata): AktarKontrol.

public struct AktarDosya: Codable, Equatable, Sendable {
    public var fid: Int
    public var ad: String
    public var boyut: Int64
    public var tur: String
    /// Degisme zamani, epoch sn.
    public var degisme: Int64?

    public static let bilinmeyenTur = "application/octet-stream"

    public init(fid: Int, ad: String, boyut: Int64, tur: String = AktarDosya.bilinmeyenTur, degisme: Int64? = nil) {
        self.fid = fid; self.ad = ad; self.boyut = boyut; self.tur = tur; self.degisme = degisme
    }
}

public struct AktarTeklif: Codable, Equatable, Sendable {
    public var aid: String
    public var dosyalar: [AktarDosya]
    public var toplam: Int64
    public var port: Int?

    public init(aid: String, dosyalar: [AktarDosya], toplam: Int64, port: Int? = nil) {
        self.aid = aid; self.dosyalar = dosyalar; self.toplam = toplam; self.port = port
    }

    public static let enFazlaDosya = 10_000

    /// fid'ler 0'dan ardisik, boyutlar negatif degil, en az bir dosya.
    public var gecerli: Bool {
        guard !aid.isEmpty, aid.utf8.count <= 64, !dosyalar.isEmpty, dosyalar.count <= Self.enFazlaDosya, toplam >= 0 else { return false }
        for (i, d) in dosyalar.enumerated() where d.fid != i || d.boyut < 0 { return false }
        return true
    }

    /// Dosya boyutlarinin toplami (`toplam` alanina guvenilmez).
    public var gercekToplam: Int64 { dosyalar.reduce(0) { $0 &+ max(0, $1.boyut) } }
}

public enum AktarNeden: String, Codable, Equatable, Sendable {
    case reddedildi
    case yerYok = "yer_yok"
    case kapali
}

public struct AktarYanit: Codable, Equatable, Sendable {
    public var aid: String
    public var kabul: Bool
    public var neden: AktarNeden?
    public var port: Int?

    public init(aid: String, kabul: Bool, neden: AktarNeden? = nil, port: Int? = nil) {
        self.aid = aid; self.kabul = kabul; self.neden = neden; self.port = port
    }
}

public struct AktarIptal: Codable, Equatable, Sendable {
    public var aid: String
    public init(aid: String) { self.aid = aid }
}

public enum AktarSonuc: String, Codable, Equatable, Sendable { case tamam, hata }

public struct AktarBitti: Codable, Equatable, Sendable {
    public var aid: String
    public var sonuc: AktarSonuc
    public var hatali: [Int]?

    public init(aid: String, sonuc: AktarSonuc, hatali: [Int]? = nil) {
        self.aid = aid; self.sonuc = sonuc; self.hatali = hatali
    }
}

// MARK: Veri baglantisi kontrol mesajlari

/// Veri baglantisinda 0x01 cercevesinin JSON'u. Bilinmeyen `t` icin `PeerMessageError.bilinmeyenTip` atilir (olumcul degil).
public enum AktarKontrol: Equatable, Sendable {
    /// alici -> gonderen, ilk mesaj: fid -> kaldigi ofset (yarim dosya yoksa bos).
    case devam(ofsetler: [Int: UInt64])
    /// gonderen -> alici: dosya bitti, tum dosyanin SHA-256'si (kucuk harf hex).
    case dosyaSon(fid: Int, sha256: String)
    /// alici -> gonderen: SHA uyusmadi, dosyayi bastan yolla.
    case dosyaHata(fid: Int)
}

extension AktarKontrol: Codable {
    private enum Keys: String, CodingKey { case t, ofsetler, fid, sha256 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        switch t {
        case "devam":
            let raw = try c.decodeIfPresent([String: UInt64].self, forKey: .ofsetler) ?? [:]
            var m: [Int: UInt64] = [:]
            for (k, v) in raw {
                guard let f = Int(k), f >= 0 else {
                    throw DecodingError.dataCorruptedError(forKey: .ofsetler, in: c, debugDescription: "fid sayi degil")
                }
                m[f] = v
            }
            self = .devam(ofsetler: m)
        case "dosya.son":
            self = .dosyaSon(fid: try c.decode(Int.self, forKey: .fid), sha256: try c.decode(String.self, forKey: .sha256))
        case "dosya.hata":
            self = .dosyaHata(fid: try c.decode(Int.self, forKey: .fid))
        default:
            throw PeerMessageError.bilinmeyenTip(t)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .devam(let o):
            try c.encode("devam", forKey: .t)
            var raw: [String: UInt64] = [:]
            for (k, v) in o { raw[String(k)] = v }
            try c.encode(raw, forKey: .ofsetler)
        case .dosyaSon(let fid, let sha):
            try c.encode("dosya.son", forKey: .t); try c.encode(fid, forKey: .fid); try c.encode(sha, forKey: .sha256)
        case .dosyaHata(let fid):
            try c.encode("dosya.hata", forKey: .t); try c.encode(fid, forKey: .fid)
        }
    }
}

public enum AktarKontrolCodec {
    public static func encode(_ m: AktarKontrol) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(m)
    }

    public static func decode(_ data: Data) throws -> AktarKontrol {
        do { return try JSONDecoder().decode(AktarKontrol.self, from: data) }
        catch let e as PeerMessageError { throw e }
        catch { throw PeerMessageError.gecersizJSON }
    }
}

/// Veri baglantisinin ilk cercevesi (duz JSON, sifresiz): `{"t":"aktar.baglan","aid":"..."}`.
public enum AktarBaglan {
    private struct Wire: Codable { var t: String; var aid: String }

    /// Uzunluk onekli cerceve.
    public static func encode(aid: String) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try PeerFrame.encode(try e.encode(Wire(t: "aktar.baglan", aid: aid)))
    }

    /// Cerceve yukunden aid; gecersizse nil.
    public static func decode(frame: Data) -> String? {
        guard let w = try? JSONDecoder().decode(Wire.self, from: frame), w.t == "aktar.baglan",
              !w.aid.isEmpty, w.aid.utf8.count <= 64 else { return nil }
        return w.aid
    }
}
