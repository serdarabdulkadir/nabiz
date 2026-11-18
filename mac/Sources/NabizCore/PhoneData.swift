import Foundation

// Telefon verisi modelleri: izinler, arama, kisiler, arama gecmisi, bildirimler. Tel bicimi: docs/protokol.md bolum 10.
// Hepsi yalniz bellekte tutulur; diske yazilmaz.

public enum CallStatus: String, Codable, Sendable { case bosta, caliyor, acik, araniyor }
public enum CallDirection: String, Codable, Sendable { case gelen, giden }
public enum CallLogDirection: String, Codable, Sendable { case gelen, giden, cevapsiz }
public enum NotifResult: String, Codable, Sendable { case tamam, bulunamadi, desteklenmiyor, hata }

/// Telefondaki "Mac ile paylas" izinleri (anahtar acik VE sistem izni verilmisse true). Varsayilan hepsi kapali.
public struct PermState: Codable, Equatable, Sendable {
    public var bildirimler: Bool
    public var cagriYonetimi: Bool
    public var kisiler: Bool
    public var aramaGecmisi: Bool
    public init(bildirimler: Bool = false, cagriYonetimi: Bool = false, kisiler: Bool = false, aramaGecmisi: Bool = false) {
        self.bildirimler = bildirimler; self.cagriYonetimi = cagriYonetimi
        self.kisiler = kisiler; self.aramaGecmisi = aramaGecmisi
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bildirimler = try c.decodeIfPresent(Bool.self, forKey: .bildirimler) ?? false
        cagriYonetimi = try c.decodeIfPresent(Bool.self, forKey: .cagriYonetimi) ?? false
        kisiler = try c.decodeIfPresent(Bool.self, forKey: .kisiler) ?? false
        aramaGecmisi = try c.decodeIfPresent(Bool.self, forKey: .aramaGecmisi) ?? false
    }
    public var anyOn: Bool { bildirimler || cagriYonetimi || kisiler || aramaGecmisi }
}

public struct CallState: Codable, Equatable, Sendable {
    public var durum: CallStatus
    public var yon: CallDirection?
    public var numara: String?
    public var kisiAdi: String?
    public var sureSn: Int?
    public init(durum: CallStatus, yon: CallDirection? = nil, numara: String? = nil, kisiAdi: String? = nil, sureSn: Int? = nil) {
        self.durum = durum; self.yon = yon; self.numara = numara; self.kisiAdi = kisiAdi; self.sureSn = sureSn
    }
}

public struct ContactNumber: Codable, Equatable, Sendable {
    public var no: String
    /// "cep" | "ev" | "is" | "diger"
    public var tur: String
    public init(no: String, tur: String) { self.no = no; self.tur = tur }
}

public struct ContactRecord: Codable, Equatable, Sendable, Identifiable {
    public var kid: String
    public var ad: String
    public var numaralar: [ContactNumber]
    public var favori: Bool
    public var gruplar: [String]
    /// Kucuk JPEG, standart base64 (opsiyonel).
    public var foto: String?
    public var id: String { kid }
    public init(kid: String, ad: String, numaralar: [ContactNumber], favori: Bool = false, gruplar: [String] = [], foto: String? = nil) {
        self.kid = kid; self.ad = ad; self.numaralar = numaralar; self.favori = favori; self.gruplar = gruplar; self.foto = foto
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kid = try c.decode(String.self, forKey: .kid)
        ad = try c.decode(String.self, forKey: .ad)
        numaralar = try c.decode([ContactNumber].self, forKey: .numaralar)
        favori = try c.decodeIfPresent(Bool.self, forKey: .favori) ?? false
        gruplar = try c.decodeIfPresent([String].self, forKey: .gruplar) ?? []
        foto = try c.decodeIfPresent(String.self, forKey: .foto)
    }
}

/// mac->tel: `ofset`inci kisiden baslayan sayfayi iste.
public struct ContactsSync: Codable, Equatable, Sendable {
    public var ofset: Int
    public var adet: Int?
    public init(ofset: Int, adet: Int? = nil) { self.ofset = ofset; self.adet = adet }
}

public struct ContactsPage: Codable, Equatable, Sendable {
    public var ofset: Int
    public var toplam: Int
    public var son: Bool
    public var kisiler: [ContactRecord]
    public init(ofset: Int, toplam: Int, son: Bool, kisiler: [ContactRecord]) {
        self.ofset = ofset; self.toplam = toplam; self.son = son; self.kisiler = kisiler
    }
}

public struct CallLogEntry: Codable, Equatable, Sendable {
    public var numara: String
    public var kisiAdi: String?
    public var yon: CallLogDirection
    public var zaman: Int      // epoch saniye
    public var sureSn: Int
    public init(numara: String, kisiAdi: String? = nil, yon: CallLogDirection, zaman: Int, sureSn: Int) {
        self.numara = numara; self.kisiAdi = kisiAdi; self.yon = yon; self.zaman = zaman; self.sureSn = sureSn
    }
}

extension CallLogEntry {
    /// Liste kimligi (numara + zaman).
    public var stableId: String { "\(numara)|\(zaman)" }
}

public struct CallLogSync: Codable, Equatable, Sendable {
    public var ofset: Int
    public var adet: Int?
    public init(ofset: Int, adet: Int? = nil) { self.ofset = ofset; self.adet = adet }
}

public struct CallLogPage: Codable, Equatable, Sendable {
    public var ofset: Int
    public var toplam: Int
    public var son: Bool
    public var kayitlar: [CallLogEntry]
    public init(ofset: Int, toplam: Int, son: Bool, kayitlar: [CallLogEntry]) {
        self.ofset = ofset; self.toplam = toplam; self.son = son; self.kayitlar = kayitlar
    }
}

/// Telefon bildirimi (StatusBarNotification ozeti).
public struct PhoneNotification: Codable, Equatable, Sendable, Identifiable {
    public var anahtar: String
    public var paket: String
    public var uygulama: String
    public var baslik: String?
    public var metin: String?
    public var zaman: Int      // epoch saniye
    public var yanitlanabilir: Bool
    public var kapatilabilir: Bool
    /// En cok 64 px PNG, standart base64.
    public var ikon: String?
    public var id: String { anahtar }
    public init(anahtar: String, paket: String, uygulama: String, baslik: String? = nil, metin: String? = nil, zaman: Int,
                yanitlanabilir: Bool = false, kapatilabilir: Bool = true, ikon: String? = nil) {
        self.anahtar = anahtar; self.paket = paket; self.uygulama = uygulama; self.baslik = baslik; self.metin = metin
        self.zaman = zaman; self.yanitlanabilir = yanitlanabilir; self.kapatilabilir = kapatilabilir; self.ikon = ikon
    }
}

/// Bildirim listesi mantigi (saf): en yeni once, en cok 50, ayni anahtar yer degistirir.
public struct NotificationFeed: Equatable, Sendable {
    public static let limit = 50
    public private(set) var items: [PhoneNotification] = []

    public init() {}

    /// Oturum basi tam liste.
    public mutating func replace(with list: [PhoneNotification]) {
        var seen = Set<String>()
        items = list.filter { seen.insert($0.anahtar).inserted }
        normalize()
    }

    /// Yeni ya da guncellenen bildirim. Icerik degistiyse true: anahtar yeni, ya da baslik/metin farkli
    /// (zaman geri gitmiyorsa). Ayni icerikte false (banner gerekmez).
    @discardableResult
    public mutating func posted(_ n: PhoneNotification) -> Bool {
        let changed: Bool
        if let i = items.firstIndex(where: { $0.anahtar == n.anahtar }) {
            let old = items[i]
            changed = n.zaman >= old.zaman && (n.baslik != old.baslik || n.metin != old.metin)
            items[i] = n
        } else { items.append(n); changed = true }
        normalize()
        return changed
    }

    public mutating func removed(_ anahtar: String) { items.removeAll { $0.anahtar == anahtar } }
    public mutating func clear() { items = [] }
    public func contains(_ anahtar: String) -> Bool { items.contains { $0.anahtar == anahtar } }

    private mutating func normalize() {
        items = items.enumerated()
            .sorted { $0.element.zaman != $1.element.zaman ? $0.element.zaman > $1.element.zaman : $0.offset < $1.offset }
            .prefix(Self.limit).map(\.element)
    }
}
