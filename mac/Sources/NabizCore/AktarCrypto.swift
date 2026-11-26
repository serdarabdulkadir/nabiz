import Foundation
import CryptoKit

// Aktar veri baglantisi sifreleme cekirdegi. Belirtim: docs/protokol.md bolum 13.
// Paket bicimi bolum 5 ile ayni (PeerCrypto / PeerCipher yeniden kullanilir); yalniz anahtarlar aid'e ozeldir.

/// Aktarimdaki rol: gonderen = `aktar.teklif`'i yollayan taraf (Mac ya da telefon olabilir).
public enum AktarRole: Sendable { case gonderen, alici }

public struct AktarKeys: Sendable {
    /// okm[0..32): gonderen -> alici.
    public let senderToReceiver: SymmetricKey
    /// okm[32..64): alici -> gonderen.
    public let receiverToSender: SymmetricKey
}

public enum AktarCrypto {
    public static let info = Data("nabiz/aktar/v1".utf8)

    /// salt = SHA-256(UTF-8 aid).
    public static func salt(aid: String) -> Data { Data(SHA256.hash(data: Data(aid.utf8))) }

    /// HKDF-SHA256(ikm = oturum okm[0..64) = macToPhone || phoneToMac, salt = SHA-256(aid), info, L = 64).
    public static func deriveKeys(sessionKeyMaterial: Data, aid: String) throws -> AktarKeys {
        guard sessionKeyMaterial.count == 64 else { throw PeerCryptoError.gecersizAnahtar }
        let okm = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: sessionKeyMaterial),
                                         salt: salt(aid: aid), info: info, outputByteCount: 64)
        let bytes = okm.withUnsafeBytes { Data($0) }
        return AktarKeys(senderToReceiver: SymmetricKey(data: Data(bytes[0..<32])),
                         receiverToSender: SymmetricKey(data: Data(bytes[32..<64])))
    }
}

/// Veri baglantisina ozel yonlu sifreleyici (sayaclar 1'den, tekrar reddi PeerCipher ile ayni).
public struct AktarCipher: Sendable {
    private var inner: PeerCipher

    public init(role: AktarRole, keys: AktarKeys) {
        let k = PeerSessionKeys(macToPhone: keys.senderToReceiver, phoneToMac: keys.receiverToSender,
                                sas: "", transcriptHash: Data())
        // PeerCipher "mac" rolu: macToPhone ile gonderir. Gonderen = s2r ile gonderir.
        inner = PeerCipher(role: role == .gonderen ? .mac : .telefon, keys: k)
    }

    public mutating func seal(_ plaintext: Data) throws -> Data { try inner.seal(plaintext) }
    public mutating func open(_ packet: Data) throws -> Data { try inner.open(packet) }
}
