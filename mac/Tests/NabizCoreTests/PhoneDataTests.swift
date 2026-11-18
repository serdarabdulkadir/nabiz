import Testing
import Foundation
@testable import NabizCore

private func dec(_ s: String) throws -> PeerEnvelope { try PeerCodec.decode(Data(s.utf8)) }
private func enc(_ e: PeerEnvelope) throws -> String { String(decoding: try PeerCodec.encode(e), as: UTF8.self) }

@Test func telefonMesajlariKodlanirVeCozulur() throws {
    #expect(try enc(PeerEnvelope(.callDial(numara: "555"), id: 2)) == #"{"id":2,"numara":"555","t":"call.dial"}"#)
    #expect(try enc(PeerEnvelope(.callState(CallState(durum: .bosta)))) == #"{"durum":"bosta","t":"call.state"}"#)
    #expect(try enc(PeerEnvelope(.permState(PermState(cagriYonetimi: false))))
            == #"{"aramaGecmisi":false,"bildirimler":false,"cagriYonetimi":false,"kisiler":false,"t":"perm.state"}"#)
    #expect(try dec(#"{"t":"call.answer","id":3}"#) == PeerEnvelope(.callAnswer, id: 3))
    #expect(try dec(#"{"t":"notif.reply","id":11,"anahtar":"k","metin":"Geliyorum"}"#)
            == PeerEnvelope(.notifReply(anahtar: "k", metin: "Geliyorum"), id: 11))
    #expect(try dec(#"{"t":"notif.result","id":11,"anahtar":"k","sonuc":"bulunamadi"}"#).message
            == .notifResult(anahtar: "k", sonuc: .bulunamadi))
    let page = try dec(#"{"t":"contacts.page","ofset":0,"toplam":1,"son":true,"kisiler":[{"kid":"1","ad":"A","numaralar":[{"no":"5","tur":"cep"}]}]}"#)
    guard case .contactsPage(let p) = page.message else { Issue.record("contacts.page"); return }
    #expect(p.kisiler.first?.favori == false && p.kisiler.first?.gruplar == [])
}

private func notif(_ key: String, _ t: Int, _ text: String = "m") -> PhoneNotification {
    PhoneNotification(anahtar: key, paket: "p", uygulama: "A", baslik: "b", metin: text, zaman: t, yanitlanabilir: false, kapatilabilir: true)
}

@Test func bildirimListesiMantigi() {
    var f = NotificationFeed()
    f.replace(with: [notif("a", 10), notif("b", 30), notif("a", 99)])   // ayni anahtar tekrarlanmaz
    #expect(f.items.map(\.anahtar) == ["b", "a"])
    #expect(f.posted(notif("c", 20)) == true)
    #expect(f.items.map(\.anahtar) == ["b", "c", "a"])
    #expect(f.posted(notif("a", 40, "yeni")) == true)   // ayni anahtar yer degistirir, icerik degisti
    #expect(f.items.map(\.anahtar) == ["a", "b", "c"] && f.items.count == 3 && f.items[0].metin == "yeni")
    f.removed("b")
    #expect(f.items.map(\.anahtar) == ["a", "c"])
    f.removed("yok")
    #expect(f.items.count == 2)
    f.clear()
    #expect(f.items.isEmpty)
}

@Test func bildirimListesiEnCok50() {
    var f = NotificationFeed()
    f.replace(with: (0..<60).map { notif("k\($0)", $0) })
    #expect(f.items.count == 50 && f.items.first?.anahtar == "k59" && f.items.last?.anahtar == "k10")
    f.posted(notif("yeni", 1000))
    #expect(f.items.count == 50 && f.items.first?.anahtar == "yeni" && !f.contains("k10"))
}

private let ayse = ContactRecord(kid: "1", ad: "Ayşe Yılmaz", numaralar: [ContactNumber(no: "+90 555 111 22 33", tur: "cep")], favori: true)
private let ibrahim = ContactRecord(kid: "2", ad: "İbrahim", numaralar: [ContactNumber(no: "0532 000 11 22", tur: "is"), ContactNumber(no: "444", tur: "diger")])

@Test func kisiDizinindeAramaVeEslestirme() {
    let idx = ContactsIndex([ibrahim, ayse])
    #expect(idx.all.map(\.kid) == ["1", "2"])
    #expect(idx.favorites.map(\.kid) == ["1"])
    #expect(idx.search("ayse").map(\.kid) == ["1"])            // aksan duyarsiz
    #expect(idx.search("IBRAHIM").map(\.kid) == ["2"])         // Turkce I / İ
    #expect(idx.search("11122").map(\.kid) == ["1"])
    #expect(idx.search("zzz").isEmpty)
    #expect(idx.match(number: "05551112233")?.kid == "1")      // ulke kodu / sifir farki
    #expect(idx.match(number: "+905320001122")?.kid == "2")
    #expect(idx.match(number: "444")?.kid == "2")
    #expect(idx.match(number: "999") == nil && idx.match(number: nil) == nil)
    #expect(ContactText.sameNumber("+90 555 111 22 33", "5551112233"))
    #expect(ContactText.dialable("+90 (555) 1-2*#") == "+905551" + "2*#")
}

@Test func kisiDizinleriArtimliSenkron() {
    var idx = ContactsIndex()
    idx.sync(with: [ayse])
    #expect(idx.count == 1)
    idx.sync(with: [ayse, ibrahim])
    #expect(idx.count == 2)
    idx.sync(with: [ayse])          // kisaldi: bastan kurulur
    #expect(idx.count == 1 && idx.match(number: "444") == nil)
    idx.reset()
    #expect(idx.count == 0 && idx.all.isEmpty)
}

@Test func ofsetSifirdaDizinSifirlanirAdDegisince() {
    var idx = ContactsIndex([ayse])
    var renamed = ayse; renamed.ad = "Zeynep"
    idx.sync(with: [renamed])                       // ayni sayi: artimli mantik atlar
    #expect(idx.match(number: "05551112233")?.ad == "Ayşe Yılmaz")
    idx.reset(); idx.sync(with: [renamed])          // ofset 0: PhoneModel reset eder
    #expect(idx.match(number: "05551112233")?.ad == "Zeynep")
}

@Test func bildirimIcerikDegistiMi() {
    var f = NotificationFeed()
    #expect(f.posted(notif("a", 10, "x")) == true)
    #expect(f.posted(notif("a", 11, "x")) == false)    // ayni icerik
    #expect(f.posted(notif("a", 12, "y")) == true)     // metin degisti
    #expect(f.posted(notif("a", 5, "z")) == false)     // zaman geri gitti
    #expect(f.items.count == 1)
}
