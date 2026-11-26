import Foundation
import CryptoKit

// Aktar alici mantigi: ad temizleme, benzersiz ad, devam ofseti, yer kontrolu, akisli SHA-256 dogrulamali yazici.
// Ag yok; dosya sistemi yalniz AktarDosyaYazici'da. Belirtim: docs/protokol.md bolum 13.

public enum AktarAd {
    public static let partUzantisi = "nabizpart"
    /// Dosya adi icin en cok UTF-8 bayt (dosya sistemi siniri 255).
    public static let enFazlaBayt = 200
    public static let varsayilanAd = "dosya"

    /// Yol ayiricilari, kontrol karakterleri, `..` ve bastaki noktalar temizlenir; bos kalirsa "dosya".
    public static func temizle(_ ad: String) -> String {
        var s = ad
        if let last = s.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last { s = String(last) } else { s = "" }
        s = String(s.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
        s = s.replacingOccurrences(of: ":", with: "-")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return varsayilanAd }
        if s.utf8.count > enFazlaBayt {
            let (stem, ext) = parcala(s)
            var kisa = stem
            while !kisa.isEmpty && (kisa.utf8.count + ext.utf8.count) > enFazlaBayt { kisa.removeLast() }
            s = kisa.isEmpty ? varsayilanAd : kisa + ext
        }
        return s
    }

    /// "a.tar.gz" -> ("a.tar", ".gz"); uzantisiz -> (ad, "").
    static func parcala(_ ad: String) -> (stem: String, ext: String) {
        guard let dot = ad.lastIndex(of: "."), dot != ad.startIndex else { return (ad, "") }
        let ext = String(ad[dot...])
        guard ext.count > 1, ext.count <= 12 else { return (ad, "") }
        return (String(ad[..<dot]), ext)
    }

    /// `varMi(ad)` doluysa "stem (2).ext", "stem (3).ext" ... dener.
    public static func benzersiz(_ ad: String, varMi: (String) -> Bool) -> String {
        if !varMi(ad) { return ad }
        let (stem, ext) = parcala(ad)
        var n = 2
        while true {
            let aday = "\(stem) (\(n))\(ext)"
            if !varMi(aday) { return aday }
            n += 1
        }
    }

    /// Yarim dosya adi: aid ve fid'e ozel, deterministik (ayni aid ile yeniden baglaninca bulunur).
    public static func partAdi(aid: String, fid: Int, ad: String) -> String {
        let kisaAid = String(aid.filter { $0.isLetter || $0.isNumber }.prefix(8))
        let govde = String(temizle(ad).prefix(120))
        return "\(govde).\(kisaAid)-\(fid).\(partUzantisi)"
    }
}

public enum AktarDevam {
    /// `devam` ofsetleri: yalniz 1...boyut araligindaki yarim dosyalar kaldigi yerden surer.
    /// `partBoyutu(fid)`: o dosyanin .nabizpart boyutu (yoksa nil).
    public static func ofsetler(dosyalar: [AktarDosya], partBoyutu: (Int) -> UInt64?) -> [Int: UInt64] {
        var m: [Int: UInt64] = [:]
        for d in dosyalar {
            guard let size = partBoyutu(d.fid), size > 0, d.boyut >= 0, size <= UInt64(d.boyut) else { continue }
            m[d.fid] = size
        }
        return m
    }
}

public enum AktarYer {
    /// Bos yer okunamiyorsa (nil) engel konmaz.
    public static func yeterli(gereken: Int64, bos: Int64?) -> Bool {
        guard let bos else { return true }
        return bos >= gereken
    }
}

public enum AktarHex {
    public static func string<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum AktarYazmaHatasi: Error, Equatable, Sendable {
    case ofsetUyusmuyor(beklenen: UInt64, gelen: UInt64)
    case tasma
    case kapali
    case io(String)
}

public enum AktarBitis: Equatable, Sendable {
    /// Dogrulandi, hedefe tasindi (benzersiz ad, degisme tarihi uygulandi).
    case tamam(URL)
    /// SHA-256 uymadi: yarim dosya silindi, dosya bastan istenmeli.
    case shaUyusmuyor
    /// Beklenen boyuta ulasilmadi.
    case eksik
}

/// Tek dosyanin alici tarafi: .nabizpart'a yazar, akisla SHA-256 hesaplar, bitince dogrulayip tasir.
/// Tek seri kuyruktan kullanilmalidir (kendi kilidi yok).
public final class AktarDosyaYazici: @unchecked Sendable {
    public let fid: Int
    public let boyut: UInt64
    public let partURL: URL
    public private(set) var yazilan: UInt64 = 0

    private let ad: String
    private let degisme: Int64?
    private var handle: FileHandle?
    private var hasher = SHA256()

    /// `devamEt`: dosyada kaldigi ofset. Diskteki parca daha kisaysa bastan baslar; uzunsa kesilir.
    /// Devam ederken mevcut baytlar okunup SHA-256 durumu yeniden kurulur.
    public init(partURL: URL, ad: String, boyut: Int64, degisme: Int64?, fid: Int, devamEt: UInt64) throws {
        self.partURL = partURL
        self.ad = AktarAd.temizle(ad)
        self.boyut = UInt64(max(0, boyut))
        self.degisme = degisme
        self.fid = fid
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: partURL.path) {
                guard fm.createFile(atPath: partURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                    throw AktarYazmaHatasi.io("olusturulamadi")
                }
            }
            let h = try FileHandle(forUpdating: partURL)
            handle = h
            let diskBoyut = try h.seekToEnd()
            var start = min(devamEt, diskBoyut, self.boyut)
            if start > 0 {
                try h.seek(toOffset: 0)
                var kalan = start
                while kalan > 0 {
                    let n = Int(min(kalan, 1 << 20))
                    guard let part = try h.read(upToCount: n), !part.isEmpty else { start -= kalan; break }
                    hasher.update(data: part)
                    kalan -= UInt64(part.count)
                }
            }
            try h.truncate(atOffset: start)
            try h.seek(toOffset: start)
            yazilan = start
        } catch let e as AktarYazmaHatasi {
            throw e
        } catch {
            throw AktarYazmaHatasi.io(error.localizedDescription)
        }
    }

    /// Veri parcasini yazar; ofset tam `yazilan` olmali (araya bosluk / geri yazma yok).
    public func yaz(ofset: UInt64, bayt: Data) throws {
        guard let handle else { throw AktarYazmaHatasi.kapali }
        guard ofset == yazilan else { throw AktarYazmaHatasi.ofsetUyusmuyor(beklenen: yazilan, gelen: ofset) }
        guard yazilan + UInt64(bayt.count) <= boyut else { throw AktarYazmaHatasi.tasma }
        do { try handle.write(contentsOf: bayt) } catch { throw AktarYazmaHatasi.io(error.localizedDescription) }
        hasher.update(data: bayt)
        yazilan += UInt64(bayt.count)
    }

    /// Su ana dek yazilan baytlarin SHA-256'si (kucuk harf hex).
    public var sha256: String { AktarHex.string(hasher.finalize()) }

    /// Dosya tamamlandi: SHA-256 uyuyorsa `hedefKlasor`e benzersiz adla tasir ve degisme tarihini uygular.
    public func bitir(sha256 beklenen: String, hedefKlasor: URL) throws -> AktarBitis {
        guard yazilan == boyut else { return .eksik }
        let hesap = self.sha256
        try? handle?.close(); handle = nil
        let fm = FileManager.default
        guard hesap == beklenen.lowercased() else {
            try? fm.removeItem(at: partURL)
            return .shaUyusmuyor
        }
        let son = AktarAd.benzersiz(ad) { fm.fileExists(atPath: hedefKlasor.appendingPathComponent($0).path) }
        let hedef = hedefKlasor.appendingPathComponent(son)
        do {
            try fm.moveItem(at: partURL, to: hedef)
            if let degisme {
                try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(degisme))], ofItemAtPath: hedef.path)
            }
        } catch {
            throw AktarYazmaHatasi.io(error.localizedDescription)
        }
        return .tamam(hedef)
    }

    /// Dosyayi kapatir; `sil` ise yarim dosya da silinir.
    public func kapat(sil: Bool) {
        try? handle?.close(); handle = nil
        if sil { try? FileManager.default.removeItem(at: partURL) }
    }
}
