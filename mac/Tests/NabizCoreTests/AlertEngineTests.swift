import Testing
import Foundation
@testable import NabizCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ sec: Double) -> Date { t0.addingTimeInterval(sec) }

private func snap(level: Int? = nil, charging: Bool = false, temp: Double? = nil, disk: (UInt64, UInt64)? = nil,
                  cpu: Int? = nil, pressure: String? = nil, thermal: String? = nil) -> Snapshot {
    Snapshot(ts: 0,
             cpu: cpu.map { CPUStats(total: $0, cores: []) },
             mem: pressure.map { MemStats(used: 1, total: 2, pressure: $0) },
             disk: disk.map { DiskStats(used: $0.0, total: $0.1) },
             battery: level.map { BatteryStats(level: $0, charging: charging, temp: temp) },
             thermal: thermal)
}

private func engine(_ id: AlertRuleID, _ subject: AlertSubject, esik: Int? = nil, sure: Int? = nil) -> AlertEngine {
    var c = AlertConfig()
    c.rules[AlertKey(id, subject)] = AlertRuleConfig(on: true, esik: esik ?? id.esikVarsayilan, sureDk: sure ?? id.sureVarsayilan)
    return AlertEngine(config: c)
}

@Test func pilDusukAtarVeBaslikMetinDogru() {
    var e = engine(.pilDusuk, .telefon)
    let f = e.evaluate(snapshot: snap(level: 18), subject: .telefon, deviceName: "Redmi", now: t0, receivedAt: t0)
    #expect(f.count == 1)
    #expect(f[0].baslik == "Redmi: Pil azaldı")
    #expect(f[0].metin == "%18 kaldı, şarjda değil.")
}

@Test func pilDusukSarjdaAtmaz() {
    var e = engine(.pilDusuk, .mac)
    #expect(e.evaluate(snapshot: snap(level: 10, charging: true), subject: .mac, deviceName: "M", now: t0).isEmpty)
}

@Test func pilDusukHisterezisVeSoguma() {
    var e = engine(.pilDusuk, .mac)
    #expect(e.evaluate(snapshot: snap(level: 20), subject: .mac, deviceName: "M", now: at(0)).count == 1)
    // Esik+5 altinda kapanmaz: tekrar atmaz
    #expect(e.evaluate(snapshot: snap(level: 22), subject: .mac, deviceName: "M", now: at(60)).isEmpty)
    #expect(e.evaluate(snapshot: snap(level: 19), subject: .mac, deviceName: "M", now: at(120)).isEmpty)
    // Kapanir (>= 25), yeniden duser ama 30 dk dolmadi
    #expect(e.evaluate(snapshot: snap(level: 25), subject: .mac, deviceName: "M", now: at(180)).isEmpty)
    #expect(e.evaluate(snapshot: snap(level: 19), subject: .mac, deviceName: "M", now: at(240)).isEmpty)
    // Kapan ve 30 dk sonra tekrar
    #expect(e.evaluate(snapshot: snap(level: 30), subject: .mac, deviceName: "M", now: at(300)).isEmpty)
    #expect(e.evaluate(snapshot: snap(level: 15), subject: .mac, deviceName: "M", now: at(1900)).count == 1)
}

@Test func pilDusukSarjaTakilincaKapanir() {
    var e = engine(.pilDusuk, .mac)
    _ = e.evaluate(snapshot: snap(level: 10), subject: .mac, deviceName: "M", now: at(0))
    _ = e.evaluate(snapshot: snap(level: 11, charging: true), subject: .mac, deviceName: "M", now: at(60))
    #expect(e.states[AlertKey(.pilDusuk, .mac)]?.aktif == false)
    #expect(e.evaluate(snapshot: snap(level: 10), subject: .mac, deviceName: "M", now: at(3600)).count == 1)
}

@Test func pilDolduKosulVeVarsayilanKapali() {
    #expect(AlertConfig().rule(.pilDoldu, .mac).on == false)
    var e = engine(.pilDoldu, .telefon, esik: 100)
    #expect(e.evaluate(snapshot: snap(level: 99, charging: true), subject: .telefon, deviceName: "P", now: t0, receivedAt: t0).isEmpty)
    let f = e.evaluate(snapshot: snap(level: 100, charging: true), subject: .telefon, deviceName: "P", now: at(10), receivedAt: at(10))
    #expect(f.first?.ruleId == .pilDoldu)
    // Sarj biterse kapanir
    #expect(e.evaluate(snapshot: snap(level: 100, charging: false), subject: .telefon, deviceName: "P", now: at(20), receivedAt: at(20)).isEmpty)
    #expect(e.states[AlertKey(.pilDoldu, .telefon)]?.aktif == false)
}

@Test func diskDoluHisterezis() {
    var e = engine(.diskDolu, .mac, esik: 90)
    let f = e.evaluate(snapshot: snap(disk: (455_000_000_000, 500_000_000_000)), subject: .mac, deviceName: "M", now: at(0))
    #expect(f.first?.metin == "Disk %91 dolu, 45 GB boş.")
    // 89 hala >= 88: kapanmadi
    _ = e.evaluate(snapshot: snap(disk: (445_000_000_000, 500_000_000_000)), subject: .mac, deviceName: "M", now: at(10))
    #expect(e.states[AlertKey(.diskDolu, .mac)]?.aktif == true)
    // 87 < 88: kapanir
    _ = e.evaluate(snapshot: snap(disk: (435_000_000_000, 500_000_000_000)), subject: .mac, deviceName: "M", now: at(20))
    #expect(e.states[AlertKey(.diskDolu, .mac)]?.aktif == false)
}

@Test func cpuSureSarti() {
    var e = engine(.cpuYuksek, .mac, esik: 90, sure: 2)
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(0)).isEmpty)
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(60)).isEmpty)
    let f = e.evaluate(snapshot: snap(cpu: 94), subject: .mac, deviceName: "M", now: at(125))
    #expect(f.count == 1)
    #expect(f[0].metin == "İşlemci 2 dakikadır %94.")
}

@Test func cpuKesintiSureyiSifirlar() {
    var e = engine(.cpuYuksek, .mac, esik: 90, sure: 2)
    _ = e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(0))
    _ = e.evaluate(snapshot: snap(cpu: 50), subject: .mac, deviceName: "M", now: at(60))
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(100)).isEmpty)
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(200)).isEmpty)
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(225)).count == 1)
}

@Test func cpuHisterezisEsikMinusOn() {
    var e = engine(.cpuYuksek, .mac, esik: 90, sure: 1)
    _ = e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(0))
    #expect(e.evaluate(snapshot: snap(cpu: 95), subject: .mac, deviceName: "M", now: at(61)).count == 1)
    _ = e.evaluate(snapshot: snap(cpu: 85), subject: .mac, deviceName: "M", now: at(70))   // 80..89: kapanmaz
    #expect(e.states[AlertKey(.cpuYuksek, .mac)]?.aktif == true)
    _ = e.evaluate(snapshot: snap(cpu: 79), subject: .mac, deviceName: "M", now: at(80))
    #expect(e.states[AlertKey(.cpuYuksek, .mac)]?.aktif == false)
}

@Test func bellekKritik() {
    var e = engine(.bellekKritik, .mac)
    #expect(e.evaluate(snapshot: snap(pressure: "warn"), subject: .mac, deviceName: "M", now: at(0)).isEmpty)
    #expect(e.evaluate(snapshot: snap(pressure: "critical"), subject: .mac, deviceName: "M", now: at(10)).count == 1)
    #expect(e.evaluate(snapshot: snap(pressure: "critical"), subject: .mac, deviceName: "M", now: at(20)).isEmpty)
}

@Test func sicakTelefonVeHisterezis() {
    var e = engine(.sicak, .telefon, esik: 42)
    let f = e.evaluate(snapshot: snap(level: 50, temp: 44.2), subject: .telefon, deviceName: "P", now: t0, receivedAt: t0)
    #expect(f.first?.metin == "Pil 44,2°C.")
    _ = e.evaluate(snapshot: snap(level: 50, temp: 40.5), subject: .telefon, deviceName: "P", now: at(5), receivedAt: at(5))
    #expect(e.states[AlertKey(.sicak, .telefon)]?.aktif == true)   // 40.5 >= 40
    _ = e.evaluate(snapshot: snap(level: 50, temp: 39.9), subject: .telefon, deviceName: "P", now: at(10), receivedAt: at(10))
    #expect(e.states[AlertKey(.sicak, .telefon)]?.aktif == false)
}

@Test func sicakMacdeUygulanmaz() {
    #expect(AlertRuleID.sicak.uygulanir(.mac) == false)
    #expect(AlertRuleID.cpuYuksek.uygulanir(.telefon) == false)
    #expect(AlertRuleID.baglantiKoptu.uygulanir(.mac) == false)
}

@Test func ilkOrnektaKosulDogruysaAtar() {
    var e = engine(.diskDolu, .mac)
    #expect(e.evaluate(snapshot: snap(disk: (99, 100)), subject: .mac, deviceName: "M", now: t0).count == 1)
}

@Test func kapaliKuralAtmaz() {
    var e = AlertEngine(config: AlertConfig())   // cpu varsayilan kapali
    #expect(e.evaluate(snapshot: snap(cpu: 100), subject: .mac, deviceName: "M", now: t0).isEmpty)
    #expect(e.evaluate(snapshot: snap(cpu: 100), subject: .mac, deviceName: "M", now: at(1000)).isEmpty)
}

@Test func karsiVeriEskiyseVeyaHazirDegilseDegerlendirilmez() {
    var e = engine(.pilDusuk, .telefon)
    #expect(e.evaluate(snapshot: snap(level: 5), subject: .telefon, deviceName: "P", now: at(200), receivedAt: t0).isEmpty)
    #expect(e.evaluate(snapshot: snap(level: 5), subject: .telefon, deviceName: "P", now: at(10), receivedAt: at(10), ready: false).isEmpty)
    #expect(e.states[AlertKey(.pilDusuk, .telefon)]?.aktif != true)
    #expect(e.evaluate(snapshot: snap(level: 5), subject: .telefon, deviceName: "P", now: at(100), receivedAt: t0).count == 1)
}

@Test func baglantiKoptu() {
    var e = engine(.baglantiKoptu, .telefon, esik: 10)
    #expect(e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: t0, now: at(9 * 60)).isEmpty)
    let f = e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: t0, now: at(15 * 60))
    #expect(f.first?.metin == "15 dakikadır görülmedi.")
    #expect(f.first?.baslik == "P: Bağlantı koptu")
    #expect(e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: t0, now: at(16 * 60)).isEmpty)
    // Tekrar gorulunce kapanir
    _ = e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: at(17 * 60), now: at(17 * 60))
    #expect(e.states[AlertKey(.baglantiKoptu, .telefon)]?.aktif == false)
}

@Test func baglantiKoptuUykuylaAtmaz() {
    var e = engine(.baglantiKoptu, .telefon, esik: 10)
    #expect(e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: t0, lastDropWasSleep: true, now: at(3600)).isEmpty)
    #expect(e.evaluateConnection(subject: .telefon, deviceName: "P", lastSeen: nil, now: at(3600)).isEmpty)
}

@Test func kalicıDurumKorunurSogumaYenidenBaslatmadaDa() {
    var e = engine(.diskDolu, .mac)
    e.states[AlertKey(.diskDolu, .mac)] = AlertState(aktif: false, son: Int(t0.timeIntervalSince1970) - 60)
    #expect(e.evaluate(snapshot: snap(disk: (99, 100)), subject: .mac, deviceName: "M", now: t0).isEmpty)
}
