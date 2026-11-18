import Testing
import Foundation
@testable import NabizCore

private func json(_ e: PeerEnvelope) throws -> String { String(decoding: try PeerCodec.encode(e), as: UTF8.self) }

@Test func ornekJSONKodlama() throws {
    #expect(try json(PeerEnvelope(.ping, id: 1)) == #"{"id":1,"t":"ping"}"#)
    #expect(try json(PeerEnvelope(.sub(aralikSn: 2))) == #"{"aralikSn":2,"t":"sub"}"#)
    #expect(try json(PeerEnvelope(.cmd(.kilitle), id: 3)) == #"{"eylem":"kilitle","id":3,"t":"cmd"}"#)
    #expect(try json(PeerEnvelope(.cmdResult(eylem: .uyut, sonuc: .kapali), id: 4))
            == #"{"eylem":"uyut","id":4,"sonuc":"kapali","t":"cmd.result"}"#)
    #expect(try json(PeerEnvelope(.error(PeerError(kod: "bilinmeyen_tip", mesaj: "x")))) == #"{"kod":"bilinmeyen_tip","mesaj":"x","t":"error"}"#)
    #expect(try json(PeerEnvelope(.error(PeerError(kod: "k")))) == #"{"kod":"k","t":"error"}"#)   // null yazilmaz
}

@Test func helloKodlamaVeCozme() throws {
    let h = PeerHello(ad: "MacBook", surum: "0.2.0", cihazId: "abc", platform: "mac", model: "MacBook Air (M4)")
    let s = try json(PeerEnvelope(.hello(h)))
    #expect(s == #"{"ad":"MacBook","cihazId":"abc","model":"MacBook Air (M4)","platform":"mac","protokol":1,"surum":"0.2.0","t":"hello"}"#)
    #expect(try PeerCodec.decode(Data(s.utf8)).message == .hello(h))
    let noModel = try PeerCodec.decode(Data(#"{"t":"hello","ad":"P","surum":"1","protokol":1,"cihazId":"x","platform":"android"}"#.utf8))
    #expect(noModel.message == .hello(PeerHello(ad: "P", surum: "1", cihazId: "x", platform: "android")))
}

@Test func statsSnapshotJSON() throws {
    let snap = Snapshot(ts: 1_700_000_000,
                        mem: MemStats(used: 4_000_000_000, total: 8_000_000_000),
                        disk: DiskStats(used: 100, total: 200),
                        battery: BatteryStats(level: 76, charging: false, health: 90, cycles: 120, minutes: 300, temp: 32.5),
                        net: NetStats(up: 10, down: 20), uptime: 3600, thermal: "warn")
    let s = try json(PeerEnvelope(.stats(snap), id: 7))
    #expect(!s.contains("null") && !s.contains("cpu"))
    let back = try PeerCodec.decode(Data(s.utf8))
    #expect(back == PeerEnvelope(.stats(snap), id: 7))
    // Android'den gelen ek/bilinmeyen alanlar yok sayilir.
    let android = #"{"t":"stats","snap":{"ts":5,"battery":{"level":50,"charging":true,"temp":30.1,"ekstra":1},"thermal":"normal","yeni":true}}"#
    let m = try PeerCodec.decode(Data(android.utf8))
    #expect(m.message == .stats(Snapshot(ts: 5, battery: BatteryStats(level: 50, charging: true, temp: 30.1), thermal: "normal")))
}

@Test func subAraligiSikistirilirVeBilinmeyenTip() throws {
    #expect(try PeerCodec.decode(Data(#"{"t":"sub","aralikSn":500}"#.utf8)).message == .sub(aralikSn: 60))
    #expect(try PeerCodec.decode(Data(#"{"t":"sub","aralikSn":0}"#.utf8)).message == .sub(aralikSn: 1))
    #expect(throws: PeerMessageError.bilinmeyenTip("xyz.bilinmeyen")) {
        try PeerCodec.decode(Data(#"{"id":2,"t":"xyz.bilinmeyen"}"#.utf8))
    }
    #expect(throws: PeerMessageError.gecersizJSON) { try PeerCodec.decode(Data("%%".utf8)) }
    #expect(throws: PeerMessageError.gecersizJSON) { try PeerCodec.decode(Data(#"{"t":"cmd","eylem":"patlat"}"#.utf8)) }
}

@Test func macStateVeUyandirJSON() throws {
    let m = PeerEnvelope(.macState(kilitli: true, ekranKapali: false, uykuyaGidiyor: false))
    let s = try json(m)
    #expect(s == #"{"ekranKapali":false,"kilitli":true,"t":"mac.state","uykuyaGidiyor":false}"#)
    #expect(try PeerCodec.decode(Data(s.utf8)) == m)
    #expect(try json(PeerEnvelope(.cmd(.uyandir), id: 9)) == #"{"eylem":"uyandir","id":9,"t":"cmd"}"#)
    #expect(try PeerCodec.decode(Data(#"{"t":"cmd","eylem":"uyandir"}"#.utf8)).message == .cmd(.uyandir))
}
