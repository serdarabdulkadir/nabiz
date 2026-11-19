import Testing
import Foundation
@testable import NabizCore

@Test func ilkBaglantiAdayOlurDogrulaninceAktif() {
    var s = ConnectionSlots()
    #expect(s.opened(1) == .aday)
    #expect(s.opened(2) == .reddet)                  // en cok 1 aday
    let r = s.promote(1)
    #expect(r.promoted && r.replaced == nil && s.active == 1 && s.candidate == nil)
}

@Test func yeniAdayEskiAktifiDogrulanincaDusurur() {
    var s = ConnectionSlots()
    _ = s.opened(1); _ = s.promote(1)
    #expect(s.opened(2) == .aday)
    #expect(s.active == 1)                           // dogrulanana dek eski yerinde
    let r = s.promote(2)
    #expect(r.promoted && r.replaced == 1 && s.active == 2)
    #expect(s.closed(1) == false)                    // eski zaten dusmustu
}

@Test func adayKapaninEskiAktifKalir() {
    var s = ConnectionSlots()
    _ = s.opened(1); _ = s.promote(1); _ = s.opened(2)
    #expect(s.closed(2) == false && s.active == 1 && s.candidate == nil)
    #expect(s.opened(3) == .aday)
    #expect(s.promote(9).promoted == false)          // aday olmayan terfi etmez
    #expect(s.closed(1) == true && s.active == nil)
}

@Test func kesifIstegiVeYaniti() throws {
    #expect(PeerDiscovery.isRequest(Data(#"{"t":"kesif","v":1}"#.utf8)))
    #expect(!PeerDiscovery.isRequest(Data(#"{"t":"kesif","v":2}"#.utf8)))
    #expect(!PeerDiscovery.isRequest(Data(#"{"t":"baska","v":1}"#.utf8)))
    #expect(!PeerDiscovery.isRequest(Data("%%".utf8)))
    let r = try #require(PeerDiscovery.reply(id: "abc", ad: "Mac", port: 47821))
    #expect(String(decoding: r, as: UTF8.self) == #"{"ad":"Mac","id":"abc","port":47821,"t":"kesif.yanit","v":1}"#)
    #expect(PeerDiscovery.port == 47822)
}
