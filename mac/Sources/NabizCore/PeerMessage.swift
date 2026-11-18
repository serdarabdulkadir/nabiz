import Foundation

// Kanal mesajlari. Tel bicimi: docs/protokol.md bolum 7. Her mesaj {"t":"<tip>","id":n,...alanlar}.

public enum PeerMessageError: Error, Equatable, Sendable {
    case bilinmeyenTip(String)
    case gecersizJSON
}

public struct PeerHello: Codable, Equatable, Sendable {
    public var ad: String
    public var surum: String
    public var protokol: Int
    public var cihazId: String
    public var platform: String   // "mac" | "android"
    public var model: String?
    public init(ad: String, surum: String, protokol: Int = 1, cihazId: String, platform: String, model: String? = nil) {
        self.ad = ad; self.surum = surum; self.protokol = protokol; self.cihazId = cihazId
        self.platform = platform; self.model = model
    }
}

public enum PeerCommand: String, Codable, Sendable { case yenile, kilitle, uyut, uyandir }
public enum PeerCommandResult: String, Codable, Sendable { case tamam, kapali, hata }

public struct PeerError: Codable, Equatable, Sendable {
    public var kod: String
    public var mesaj: String?
    public init(kod: String, mesaj: String? = nil) { self.kod = kod; self.mesaj = mesaj }
}

public enum PeerMessage: Equatable, Sendable {
    case hello(PeerHello)
    case ping
    case pong
    case stats(Snapshot)
    case sub(aralikSn: Int)
    case cmd(PeerCommand)
    case macState(kilitli: Bool, ekranKapali: Bool, uykuyaGidiyor: Bool)
    case cmdResult(eylem: PeerCommand, sonuc: PeerCommandResult)
    case error(PeerError)

    public var type: String {
        switch self {
        case .hello: "hello"
        case .ping: "ping"
        case .pong: "pong"
        case .stats: "stats"
        case .sub: "sub"
        case .cmd: "cmd"
        case .macState: "mac.state"
        case .cmdResult: "cmd.result"
        case .error: "error"
        }
    }
}

/// `{"t":..., "id":...}` zarfi + mesaj.
public struct PeerEnvelope: Codable, Equatable, Sendable {
    public var id: Int?
    public var message: PeerMessage

    public init(_ message: PeerMessage, id: Int? = nil) { self.message = message; self.id = id }

    private enum Keys: String, CodingKey { case t, id, snap, aralikSn, eylem, sonuc, kilitli, ekranKapali, uykuyaGidiyor }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let t = try c.decode(String.self, forKey: .t)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        switch t {
        case "hello": message = .hello(try PeerHello(from: decoder))
        case "ping": message = .ping
        case "pong": message = .pong
        case "stats": message = .stats(try c.decode(Snapshot.self, forKey: .snap))
        case "sub":
            let n = try c.decode(Int.self, forKey: .aralikSn)
            message = .sub(aralikSn: min(60, max(1, n)))
        case "cmd": message = .cmd(try c.decode(PeerCommand.self, forKey: .eylem))
        case "mac.state":
            message = .macState(kilitli: try c.decode(Bool.self, forKey: .kilitli),
                                ekranKapali: try c.decode(Bool.self, forKey: .ekranKapali),
                                uykuyaGidiyor: try c.decodeIfPresent(Bool.self, forKey: .uykuyaGidiyor) ?? false)
        case "cmd.result":
            message = .cmdResult(eylem: try c.decode(PeerCommand.self, forKey: .eylem),
                                 sonuc: try c.decode(PeerCommandResult.self, forKey: .sonuc))
        case "error": message = .error(try PeerError(from: decoder))
        default: throw PeerMessageError.bilinmeyenTip(t)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(message.type, forKey: .t)
        try c.encodeIfPresent(id, forKey: .id)
        switch message {
        case .hello(let h): try h.encode(to: encoder)
        case .ping, .pong: break
        case .stats(let s): try c.encode(s, forKey: .snap)
        case .sub(let n): try c.encode(n, forKey: .aralikSn)
        case .cmd(let e): try c.encode(e, forKey: .eylem)
        case .macState(let k, let e, let u):
            try c.encode(k, forKey: .kilitli); try c.encode(e, forKey: .ekranKapali); try c.encode(u, forKey: .uykuyaGidiyor)
        case .cmdResult(let e, let r): try c.encode(e, forKey: .eylem); try c.encode(r, forKey: .sonuc)
        case .error(let e): try e.encode(to: encoder)
        }
    }
}

public enum PeerCodec {
    public static func encode(_ envelope: PeerEnvelope) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> PeerEnvelope {
        do { return try JSONDecoder().decode(PeerEnvelope.self, from: data) }
        catch let e as PeerMessageError { throw e }
        catch { throw PeerMessageError.gecersizJSON }
    }
}
