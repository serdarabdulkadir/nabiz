import Testing
@testable import NabizCore

@Test func rttOlcumuVeOrtanca() {
    var t = RTTTracker()
    #expect(t.medianMs == nil)
    var now = 100.0
    for ms in [10.0, 50.0, 20.0, 30.0, 40.0] {
        let id = t.pingSent(at: now)
        #expect(t.pongReceived(id: id, at: now + ms / 1000) != nil)
        now += 15
    }
    #expect(t.medianMs == 30)
    // 6. olcum: pencere son 5 (50,20,30,40,100) -> ortanca 40.
    let id = t.pingSent(at: now)
    #expect(t.pongReceived(id: id, at: now + 0.1) == 100)
    #expect(t.medianMs == 40)
}

@Test func rttIdsizVeBilinmeyenPongYoksayilir() {
    var t = RTTTracker()
    let id = t.pingSent(at: 0)
    #expect(t.pongReceived(id: nil, at: 1) == nil)
    #expect(t.pongReceived(id: id + 5, at: 1) == nil)
    #expect(t.medianMs == nil)
    #expect(t.pongReceived(id: id, at: 0.012) == 12)
    #expect(t.pongReceived(id: id, at: 0.5) == nil)   // ikinci pong ayni id
    #expect(t.pingSent(at: 1) == id + 1)
}

@Test func rttSifirlamaVeCiftOrtanca() {
    var t = RTTTracker()
    for ms in [10.0, 20.0] { let i = t.pingSent(at: 0); t.pongReceived(id: i, at: ms / 1000) }
    #expect(t.medianMs == 15)
    t.reset()
    #expect(t.medianMs == nil)
}
