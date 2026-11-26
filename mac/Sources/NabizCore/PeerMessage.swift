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
    // Telefon: izinler, arama, kisiler, arama gecmisi, bildirimler (docs/protokol.md bolum 10).
    case permState(PermState)
    case callState(CallState)
    case callAnswer, callReject, callHangup
    case callDial(numara: String)
    case contactsSync(ContactsSync)
    case contactsPage(ContactsPage)
    case contactsChanged
    case callLogSync(CallLogSync)
    case callLogPage(CallLogPage)
    case callLogChanged
    case notifList([PhoneNotification])
    case notifPosted(PhoneNotification)
    case notifRemoved(anahtar: String)
    case notifDismiss(anahtar: String)
    case notifClear
    case notifReply(anahtar: String, metin: String)
    case notifResult(anahtar: String, sonuc: NotifResult)
    case aiState([AIWireProvider])
    /// tel->mac: AI verisini yenilet (bolum 12). `zorla`: gercek yenileme (en cok 15 sn'de bir).
    case aiSync(zorla: Bool)
    // Aktar: dosya aktarimi kontrol mesajlari (docs/protokol.md bolum 13).
    case aktarTeklif(AktarTeklif)
    case aktarYanit(AktarYanit)
    case aktarIptal(AktarIptal)
    case aktarBitti(AktarBitti)

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
        case .permState: "perm.state"
        case .callState: "call.state"
        case .callAnswer: "call.answer"
        case .callReject: "call.reject"
        case .callHangup: "call.hangup"
        case .callDial: "call.dial"
        case .contactsSync: "contacts.sync"
        case .contactsPage: "contacts.page"
        case .contactsChanged: "contacts.changed"
        case .callLogSync: "calllog.sync"
        case .callLogPage: "calllog.page"
        case .callLogChanged: "calllog.changed"
        case .notifList: "notif.list"
        case .notifPosted: "notif.posted"
        case .notifRemoved: "notif.removed"
        case .notifDismiss: "notif.dismiss"
        case .notifClear: "notif.clear"
        case .notifReply: "notif.reply"
        case .notifResult: "notif.result"
        case .aiState: "ai.state"
        case .aiSync: "ai.sync"
        case .aktarTeklif: "aktar.teklif"
        case .aktarYanit: "aktar.yanit"
        case .aktarIptal: "aktar.iptal"
        case .aktarBitti: "aktar.bitti"
        }
    }
}

/// `{"t":..., "id":...}` zarfi + mesaj.
public struct PeerEnvelope: Codable, Equatable, Sendable {
    public var id: Int?
    public var message: PeerMessage

    public init(_ message: PeerMessage, id: Int? = nil) { self.message = message; self.id = id }

    private enum Keys: String, CodingKey { case t, id, snap, aralikSn, eylem, sonuc, kilitli, ekranKapali, uykuyaGidiyor, numara, bildirimler, bildirim, anahtar, metin, saglayicilar, zorla }

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
        case "perm.state": message = .permState(try PermState(from: decoder))
        case "call.state": message = .callState(try CallState(from: decoder))
        case "call.answer": message = .callAnswer
        case "call.reject": message = .callReject
        case "call.hangup": message = .callHangup
        case "call.dial": message = .callDial(numara: try c.decode(String.self, forKey: .numara))
        case "contacts.sync": message = .contactsSync(try ContactsSync(from: decoder))
        case "contacts.page": message = .contactsPage(try ContactsPage(from: decoder))
        case "contacts.changed": message = .contactsChanged
        case "calllog.sync": message = .callLogSync(try CallLogSync(from: decoder))
        case "calllog.page": message = .callLogPage(try CallLogPage(from: decoder))
        case "calllog.changed": message = .callLogChanged
        case "notif.list": message = .notifList(try c.decode([PhoneNotification].self, forKey: .bildirimler))
        case "notif.posted": message = .notifPosted(try c.decode(PhoneNotification.self, forKey: .bildirim))
        case "notif.removed": message = .notifRemoved(anahtar: try c.decode(String.self, forKey: .anahtar))
        case "notif.dismiss": message = .notifDismiss(anahtar: try c.decode(String.self, forKey: .anahtar))
        case "notif.clear": message = .notifClear
        case "notif.reply":
            message = .notifReply(anahtar: try c.decode(String.self, forKey: .anahtar), metin: try c.decode(String.self, forKey: .metin))
        case "ai.state": message = .aiState(try c.decode([AIWireProvider].self, forKey: .saglayicilar))
        case "ai.sync": message = .aiSync(zorla: try c.decodeIfPresent(Bool.self, forKey: .zorla) ?? false)
        case "aktar.teklif": message = .aktarTeklif(try AktarTeklif(from: decoder))
        case "aktar.yanit": message = .aktarYanit(try AktarYanit(from: decoder))
        case "aktar.iptal": message = .aktarIptal(try AktarIptal(from: decoder))
        case "aktar.bitti": message = .aktarBitti(try AktarBitti(from: decoder))
        case "notif.result":
            message = .notifResult(anahtar: try c.decode(String.self, forKey: .anahtar), sonuc: try c.decode(NotifResult.self, forKey: .sonuc))
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
        case .permState(let p): try p.encode(to: encoder)
        case .callState(let s): try s.encode(to: encoder)
        case .callAnswer, .callReject, .callHangup, .contactsChanged, .callLogChanged, .notifClear: break
        case .callDial(let n): try c.encode(n, forKey: .numara)
        case .contactsSync(let v): try v.encode(to: encoder)
        case .contactsPage(let v): try v.encode(to: encoder)
        case .callLogSync(let v): try v.encode(to: encoder)
        case .callLogPage(let v): try v.encode(to: encoder)
        case .notifList(let l): try c.encode(l, forKey: .bildirimler)
        case .notifPosted(let n): try c.encode(n, forKey: .bildirim)
        case .notifRemoved(let a), .notifDismiss(let a): try c.encode(a, forKey: .anahtar)
        case .notifReply(let a, let m): try c.encode(a, forKey: .anahtar); try c.encode(m, forKey: .metin)
        case .notifResult(let a, let r): try c.encode(a, forKey: .anahtar); try c.encode(r, forKey: .sonuc)
        case .aiState(let l): try c.encode(l, forKey: .saglayicilar)
        case .aiSync(let z): if z { try c.encode(true, forKey: .zorla) }
        case .aktarTeklif(let v): try v.encode(to: encoder)
        case .aktarYanit(let v): try v.encode(to: encoder)
        case .aktarIptal(let v): try v.encode(to: encoder)
        case .aktarBitti(let v): try v.encode(to: encoder)
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
