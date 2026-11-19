import Foundation

/// UDP kesif (docs/protokol.md bolum 11): telefon `{"t":"kesif","v":1}` yollar, Mac unicast yanitlar.
public enum PeerDiscovery {
    public static let port: UInt16 = 47822

    /// Gecerli bir kesif istegi mi? Gecersiz / bilinmeyen paket false (yok sayilir).
    public static func isRequest(_ data: Data) -> Bool {
        guard data.count <= 512, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return o["t"] as? String == "kesif" && (o["v"] as? Int) == 1
    }

    public static func reply(id: String, ad: String, port: UInt16) -> Data? {
        struct Reply: Encodable { let t = "kesif.yanit"; let v = 1; let id: String; let ad: String; let port: Int }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try? e.encode(Reply(id: id, ad: ad, port: Int(port)))
    }
}
