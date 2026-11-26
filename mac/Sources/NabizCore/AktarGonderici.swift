import Foundation
import CryptoKit

// Aktar gonderen mantigi: dosyayi parca parca okur, tum dosyanin SHA-256'sini akisla hesaplar.
// Belirtim: docs/protokol.md bolum 13. Bellege tum dosya alinmaz.

public enum AktarOkumaHatasi: Error, Equatable, Sendable {
    case acilamadi(String)
    /// Dosya teklif edildikten sonra degisti (boyut uyusmuyor).
    case degisti
    case ofsetGecersiz
}

/// Tek dosyanin gonderen tarafi. Tek seri kuyruktan kullanilmalidir.
public final class AktarDosyaOkuyucu: @unchecked Sendable {
    public let boyut: UInt64
    public private(set) var konum: UInt64 = 0

    private let handle: FileHandle
    private var hasher = SHA256()

    /// `beklenenBoyut`: tekliftekiyle ayni olmali, degilse `.degisti`.
    public init(url: URL, beklenenBoyut: Int64) throws {
        let h: FileHandle
        let end: UInt64
        do {
            h = try FileHandle(forReadingFrom: url)
            end = try h.seekToEnd()
            try h.seek(toOffset: 0)
        } catch {
            throw AktarOkumaHatasi.acilamadi(error.localizedDescription)
        }
        guard beklenenBoyut >= 0, end == UInt64(beklenenBoyut) else {
            try? h.close()
            throw AktarOkumaHatasi.degisti
        }
        handle = h
        boyut = end
    }

    /// `ofset`ten baslar: [0, ofset) okunup yalniz SHA-256'ya katilir (gonderilmez), sonra konum `ofset` olur.
    public func basla(ofset: UInt64) throws {
        guard ofset <= boyut else { throw AktarOkumaHatasi.ofsetGecersiz }
        hasher = SHA256()
        do {
            try handle.seek(toOffset: 0)
            var kalan = ofset
            while kalan > 0 {
                guard let part = try handle.read(upToCount: Int(min(kalan, 1 << 20))), !part.isEmpty else {
                    throw AktarOkumaHatasi.degisti
                }
                hasher.update(data: part)
                kalan -= UInt64(part.count)
            }
        } catch let e as AktarOkumaHatasi {
            throw e
        } catch {
            throw AktarOkumaHatasi.acilamadi(error.localizedDescription)
        }
        konum = ofset
    }

    /// Sonraki parca (en cok `en` bayt); dosya sonunda nil. Okunan bayt SHA-256'ya katilir.
    public func sonraki(en: Int) throws -> (ofset: UInt64, bayt: Data)? {
        guard konum < boyut else { return nil }
        let n = Int(min(UInt64(en), boyut - konum))
        do {
            guard let part = try handle.read(upToCount: n), !part.isEmpty else { throw AktarOkumaHatasi.degisti }
            let ofset = konum
            hasher.update(data: part)
            konum += UInt64(part.count)
            return (ofset, part)
        } catch let e as AktarOkumaHatasi {
            throw e
        } catch {
            throw AktarOkumaHatasi.acilamadi(error.localizedDescription)
        }
    }

    /// Dosyanin tamami okunduktan sonra SHA-256 (kucuk harf hex).
    public var sha256: String { AktarHex.string(hasher.finalize()) }

    public func kapat() { try? handle.close() }
}
