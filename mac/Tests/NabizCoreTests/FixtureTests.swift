import Testing
import Foundation
import CryptoKit
@testable import NabizCore

// Ortak ornekler: docs/fixtures/*.json (Android testleri de ayni dosyalari okur).

private func fixtureURL(_ name: String, file: String = #filePath) -> URL {
    // mac/Tests/NabizCoreTests/FixtureTests.swift -> repo koku
    var url = URL(fileURLWithPath: file)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("docs/fixtures/\(name)")
}

private func loadJSON(_ name: String) throws -> [String: Any] {
    let data = try Data(contentsOf: fixtureURL(name))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func unhex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}
private func jsonEqual(_ x: Data, _ y: Data) throws -> Bool {
    let a = try JSONSerialization.jsonObject(with: x) as! NSObject
    let b = try JSONSerialization.jsonObject(with: y) as! NSObject
    return a == b
}
private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

@Test func mesajOrnekleriCozulurVeAyniJSONaKodlanir() throws {
    let root = try loadJSON("messages.json")
    let items = try #require(root["ornekler"] as? [[String: Any]])
    #expect(items.count >= 11)
    for item in items {
        let name = item["ad"] as? String ?? "?"
        let json = try #require(item["json"])
        let original = try JSONSerialization.data(withJSONObject: json)
        let env = try PeerCodec.decode(original)
        let again = try PeerCodec.encode(env)
        let same = try jsonEqual(original, again)
        #expect(same, "\(name): \(String(decoding: again, as: UTF8.self))")
    }
}

@Test func pingPongOrnegiIdTasir() throws {
    let root = try loadJSON("messages.json")
    let items = try #require(root["ornekler"] as? [[String: Any]])
    for (ad, msg) in [("ping", PeerMessage.ping), ("pong", .pong)] {
        let json = try #require(items.first { $0["ad"] as? String == ad }?["json"])
        let env = try PeerCodec.decode(try JSONSerialization.data(withJSONObject: json))
        #expect(env.message == msg)
        #expect(env.id == 7)
    }
}

@Test func elSikismaOrnegiCozulur() throws {
    let root = try loadJSON("messages.json")
    let hsObj = try #require((root["hs"] as? [String: Any])?["json"])
    let data = try JSONSerialization.data(withJSONObject: hsObj)
    let hs = try JSONDecoder().decode(PeerHandshake.self, from: data)
    #expect(hs.t == "hs" && hs.v == 1 && hs.rol == "mac" && hs.ad == "MacBook Air")
    #expect(Data(base64Encoded: hs.pub)?.count == 65)
    #expect(Data(base64Encoded: hs.nonce)?.count == PeerCrypto.nonceLength)
    // Mac'in vektordeki acik anahtari ile ayni.
    let v = try loadJSON("vectors.json")
    let kdf = try #require(v["kdf"] as? [String: String])
    #expect(hex(Data(base64Encoded: hs.pub)!) == kdf["macPub"])
    #expect(hex(Data(base64Encoded: hs.nonce)!) == kdf["macNonce"])
    // Yeniden kodlama (JSONEncoder sirali) ayni nesne.
    let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
    let again = try e.encode(hs)
    let same = try jsonEqual(data, again)
    #expect(same)
}

@Test func vektorDosyasiHKDFveKDF() throws {
    let v = try loadJSON("vectors.json")
    let h = try #require(v["hkdf"] as? [String: Any])
    let ikm = unhex(h["ikm"] as! String), salt = unhex(h["salt"] as! String), info = unhex(h["info"] as! String)
    let length = h["length"] as! Int
    let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: salt)))
    var t = Data(), okm = Data(), i: UInt8 = 1
    while okm.count < length {
        t = Data(HMAC<SHA256>.authenticationCode(for: t + info + Data([i]), using: SymmetricKey(data: prk)))
        okm += t; i += 1
    }
    #expect(hex(okm.prefix(length)) == h["okm"] as? String)

    let k = try #require(v["kdf"] as? [String: String])
    let mac = try PeerIdentity(rawPrivateKey: unhex(k["macPriv"]!))
    let phone = try PeerIdentity(rawPrivateKey: unhex(k["phonePriv"]!))
    #expect(hex(mac.publicKey) == k["macPub"])
    #expect(hex(phone.publicKey) == k["phonePub"])
    let macNonce = unhex(k["macNonce"]!), phoneNonce = unhex(k["phoneNonce"]!)
    let km = try PeerCrypto.deriveKeys(role: .mac, identity: mac, peerPublicKey: phone.publicKey, macNonce: macNonce, phoneNonce: phoneNonce)
    let kp = try PeerCrypto.deriveKeys(role: .telefon, identity: phone, peerPublicKey: mac.publicKey, macNonce: macNonce, phoneNonce: phoneNonce)
    for keys in [km, kp] {
        let m2p = keys.macToPhone.withUnsafeBytes { Data($0) }
        let p2m = keys.phoneToMac.withUnsafeBytes { Data($0) }
        #expect(hex(keys.transcriptHash) == k["salt"])
        #expect(hex(m2p) == k["macToPhone"])
        #expect(hex(p2m) == k["phoneToMac"])
        #expect(keys.sas == k["sas"])
    }
    // ECDH ortak sirri.
    let peerPub = try P256.KeyAgreement.PublicKey(x963Representation: phone.publicKey)
    let secret = try mac.privateKey.sharedSecretFromKeyAgreement(with: peerPub)
    let secretBytes = secret.withUnsafeBytes { Data($0) }
    #expect(hex(secretBytes) == k["secret"])
}

@Test func vektorDosyasiGCMveCerceve() throws {
    let v = try loadJSON("vectors.json")
    let g = try #require(v["gcm"] as? [String: Any])
    let key = SymmetricKey(data: unhex(g["key"] as! String))
    let plain = Data((g["plaintext"] as! String).utf8)
    let packet = try PeerCrypto.seal(plain, key: key, counter: UInt64(g["counter"] as! Int))
    #expect(hex(packet) == g["packet"] as? String)
    let opened = try PeerCrypto.open(unhex(g["packet"] as! String), key: key)
    #expect(opened.counter == UInt64(g["counter"] as! Int) && opened.plaintext == plain)

    let f = try #require(v["frame"] as? [String: String])
    let framed = try PeerFrame.encode(unhex(f["payload"]!))
    #expect(hex(framed) == f["framed"])
    var buf = PeerFrameBuffer()
    let frames = try buf.append(unhex(f["framed"]!))
    #expect(frames == [unhex(f["payload"]!)])
}
