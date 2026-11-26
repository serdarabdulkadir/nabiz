import Foundation

// Aktar sifreli acik metin cercevesi (docs/protokol.md bolum 13): ilk bayt tur.
//   0x01 JSON kontrol: 0x01 || json
//   0x02 veri: 0x02 || fid(uint16 BE) || ofset(uint64 BE) || bayt  (bayt en cok 512 KiB)
// Dis cerceve (4 bayt uzunluk) ve sifreleme PeerFrame / AktarCipher ile yapilir.

public enum AktarFrameError: Error, Equatable, Sendable {
    case bos
    case bilinmeyenTur(UInt8)
    case kisaVeri
    case cokBuyukVeri(Int)
    case gecersizFid(Int)
}

public enum AktarFrame: Equatable, Sendable {
    case kontrol(Data)
    case veri(fid: Int, ofset: UInt64, bayt: Data)
}

public enum AktarFraming {
    public static let kontrolTuru: UInt8 = 0x01
    public static let veriTuru: UInt8 = 0x02
    /// Veri parcasinin en buyuk bayt sayisi.
    public static let maxVeri = 512 * 1024
    /// tur(1) + fid(2) + ofset(8).
    public static let veriBasligi = 11

    public static func encodeControl(_ json: Data) -> Data {
        var out = Data(capacity: 1 + json.count)
        out.append(kontrolTuru)
        out.append(json)
        return out
    }

    public static func encodeData(fid: Int, ofset: UInt64, bayt: Data) throws -> Data {
        guard (0...Int(UInt16.max)).contains(fid) else { throw AktarFrameError.gecersizFid(fid) }
        guard bayt.count <= maxVeri else { throw AktarFrameError.cokBuyukVeri(bayt.count) }
        var out = Data(capacity: veriBasligi + bayt.count)
        out.append(veriTuru)
        withUnsafeBytes(of: UInt16(fid).bigEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: ofset.bigEndian) { out.append(contentsOf: $0) }
        out.append(bayt)
        return out
    }

    public static func decode(_ plaintext: Data) throws -> AktarFrame {
        guard !plaintext.isEmpty else { throw AktarFrameError.bos }
        let s = plaintext.startIndex
        switch plaintext[s] {
        case kontrolTuru:
            return .kontrol(Data(plaintext[(s + 1)...]))
        case veriTuru:
            guard plaintext.count >= veriBasligi else { throw AktarFrameError.kisaVeri }
            let fid = (Int(plaintext[s + 1]) << 8) | Int(plaintext[s + 2])
            var ofset: UInt64 = 0
            for i in 3..<11 { ofset = (ofset << 8) | UInt64(plaintext[s + i]) }
            let body = plaintext[(s + veriBasligi)...]   // dilim: kopya yok, ayni bellegi paylasir
            guard body.count <= maxVeri else { throw AktarFrameError.cokBuyukVeri(body.count) }
            return .veri(fid: fid, ofset: ofset, bayt: body)
        default:
            throw AktarFrameError.bilinmeyenTur(plaintext[s])
        }
    }
}
