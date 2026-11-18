// Kimlik anahtari + eslesmis telefon (pin) + cihaz kimligi. Keychain YOK (ORBIO'da donma yapti):
// ~/Library/Application Support/Nabiz/ altinda 0600 dosyalar. Belirtim: docs/protokol.md bolum 4 ve 6.
import Foundation
import NabizCore

struct PairedPhone: Codable, Equatable {
    var key: Data          // telefonun X9.63 acik anahtari (65 bayt)
    var name: String
    var model: String?
}

struct PeerStore {
    private let dir: URL

    init(directory: URL? = nil) {
        dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz", isDirectory: true)
    }

    private var identityURL: URL { dir.appendingPathComponent("identity.key") }
    private var pinURL: URL { dir.appendingPathComponent("paired.json") }
    private var deviceIdURL: URL { dir.appendingPathComponent("device-id") }

    /// Kalici P-256 kimligi; yoksa uretilip yazilir.
    func identity() -> PeerIdentity {
        if let raw = try? Data(contentsOf: identityURL), let id = try? PeerIdentity(rawPrivateKey: raw) { return id }
        let id = PeerIdentity()
        write(id.rawPrivateKey, to: identityURL)
        return id
    }

    func deviceId() -> String {
        if let s = try? String(contentsOf: deviceIdURL, encoding: .utf8), !s.isEmpty { return s }
        let s = UUID().uuidString
        write(Data(s.utf8), to: deviceIdURL)
        return s
    }

    func pairedPhone() -> PairedPhone? {
        guard let data = try? Data(contentsOf: pinURL) else { return nil }
        return try? JSONDecoder().decode(PairedPhone.self, from: data)
    }

    func savePairedPhone(_ phone: PairedPhone) {
        if let data = try? JSONEncoder().encode(phone) { write(data, to: pinURL) }
    }

    func forgetPairedPhone() {
        try? FileManager.default.removeItem(at: pinURL)
    }

    private func write(_ data: Data, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Once 0600 olusturulur, sonra icerik yazilir (gecici olarak genis izinle acik kalmaz).
        fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try? data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
