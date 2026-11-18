// Uyari kural motoru (docs/uyarilar.md). Saf: zaman ve veri disaridan verilir, bildirim gondermez.
import Foundation

public enum AlertRuleID: String, CaseIterable, Sendable {
    case pilDusuk = "pil_dusuk"
    case pilDoldu = "pil_doldu"
    case diskDolu = "disk_dolu"
    case cpuYuksek = "cpu_yuksek"
    case bellekKritik = "bellek_kritik"
    case sicak = "sicak"
    case baglantiKoptu = "baglanti_koptu"

    public var ad: String {
        switch self {
        case .pilDusuk: "Pil azaldı"
        case .pilDoldu: "Şarj doldu"
        case .diskDolu: "Depolama doluyor"
        case .cpuYuksek: "İşlemci yüksek"
        case .bellekKritik: "Bellek baskısı"
        case .sicak: "Cihaz ısındı"
        case .baglantiKoptu: "Bağlantı koptu"
        }
    }

    /// Esik araligi; esiksiz kuralda nil.
    public var esikAraligi: ClosedRange<Int>? {
        switch self {
        case .pilDusuk: 5...50
        case .pilDoldu: 80...100
        case .diskDolu: 70...99
        case .cpuYuksek: 50...100
        case .bellekKritik: nil
        case .sicak: 35...50
        case .baglantiKoptu: 2...60
        }
    }

    public var esikVarsayilan: Int {
        switch self {
        case .pilDusuk: 20
        case .pilDoldu: 100
        case .diskDolu: 90
        case .cpuYuksek: 90
        case .bellekKritik: 0
        case .sicak: 42
        case .baglantiKoptu: 10
        }
    }

    /// Yalniz cpu_yuksek: kesintisiz dakika (1-15). baglanti_koptu'nun esigi zaten dakikadir.
    public var sureAraligi: ClosedRange<Int>? { self == .cpuYuksek ? 1...15 : nil }
    public var sureVarsayilan: Int { self == .cpuYuksek ? 2 : 0 }

    public func varsayilanAcik(_ subject: AlertSubject) -> Bool {
        switch self {
        case .pilDusuk, .diskDolu: true
        case .sicak: subject == .telefon
        default: false
        }
    }

    /// Ayarlarda gosterilen ve degerlendirilen ornekler. Mac'te isi olculmez; baglanti yalniz karsi cihaz (telefon) icin.
    public func uygulanir(_ subject: AlertSubject) -> Bool {
        switch self {
        case .pilDusuk, .pilDoldu, .diskDolu: true
        case .cpuYuksek, .bellekKritik: subject == .mac
        case .sicak: subject == .telefon
        case .baglantiKoptu: subject == .telefon
        }
    }
}

public enum AlertSubject: String, CaseIterable, Sendable {
    case mac, telefon
}

public struct AlertKey: Hashable, Sendable {
    public var rule: AlertRuleID
    public var subject: AlertSubject
    public init(_ rule: AlertRuleID, _ subject: AlertSubject) { self.rule = rule; self.subject = subject }
    /// UserDefaults on eki: alert.<id>.<konu>
    public var prefix: String { "alert.\(rule.rawValue).\(subject.rawValue)" }
}

public struct AlertRuleConfig: Sendable, Equatable {
    public var on: Bool
    public var esik: Int
    public var sureDk: Int
    public init(on: Bool, esik: Int, sureDk: Int) { self.on = on; self.esik = esik; self.sureDk = sureDk }
}

public struct AlertConfig: Sendable, Equatable {
    public var rules: [AlertKey: AlertRuleConfig] = [:]
    public init(rules: [AlertKey: AlertRuleConfig] = [:]) { self.rules = rules }

    public func rule(_ id: AlertRuleID, _ subject: AlertSubject) -> AlertRuleConfig {
        rules[AlertKey(id, subject)]
            ?? AlertRuleConfig(on: id.varsayilanAcik(subject), esik: id.esikVarsayilan, sureDk: id.sureVarsayilan)
    }
}

public struct AlertState: Sendable, Equatable {
    /// Kosul su an dogru mu (histerezis).
    public var aktif = false
    /// Son bildirim epoch sn.
    public var son: Int?
    /// cpu_yuksek: kosulun kesintisiz basladigi an (bellekte tutulur).
    public var kosulBaslangic: Date?
    public init(aktif: Bool = false, son: Int? = nil, kosulBaslangic: Date? = nil) {
        self.aktif = aktif; self.son = son; self.kosulBaslangic = kosulBaslangic
    }
}

public struct AlertFire: Sendable, Equatable {
    public var baslik: String
    public var metin: String
    public var ruleId: AlertRuleID
    public var subject: AlertSubject
}

public struct AlertEngine: Sendable {
    public static let cooldown: TimeInterval = 30 * 60
    public static let maxPeerAge: TimeInterval = 2 * 60

    public var config: AlertConfig
    public var states: [AlertKey: AlertState]

    public init(config: AlertConfig = AlertConfig(), states: [AlertKey: AlertState] = [:]) {
        self.config = config; self.states = states
    }

    /// Bir cihazin Snapshot'ini degerlendirir. Karsi cihazda (`receivedAt` verilmisse) oturum `ready` ve
    /// son stats 2 dakikadan yeni olmalidir; degilse hicbir sey yapilmaz.
    public mutating func evaluate(snapshot: Snapshot, subject: AlertSubject, deviceName: String, now: Date,
                                  receivedAt: Date? = nil, ready: Bool = true) -> [AlertFire] {
        if let receivedAt {
            guard ready, now.timeIntervalSince(receivedAt) <= Self.maxPeerAge else { return [] }
        }
        var fires: [AlertFire] = []
        for id in AlertRuleID.allCases where id != .baglantiKoptu && id.uygulanir(subject) {
            let key = AlertKey(id, subject)
            let cfg = config.rule(id, subject)
            var st = states[key] ?? AlertState()
            guard cfg.on else {
                st.aktif = false; st.kosulBaslangic = nil
                states[key] = st
                continue
            }
            guard let r = check(id, snapshot, cfg, st, now) else { continue }   // veri yok: durum degismez
            st.kosulBaslangic = r.baslangic
            if let text = step(&st, cond: r.cond, clear: r.clear, text: r.text, now: now) {
                fires.append(AlertFire(baslik: "\(deviceName): \(id.ad)", metin: text, ruleId: id, subject: subject))
            }
            states[key] = st
        }
        return fires
    }

    /// baglanti_koptu: karsi cihaz `sureDk` dakikadir gorulmediyse (ve kopus uykuyaGidiyor ile degilse).
    public mutating func evaluateConnection(subject: AlertSubject, deviceName: String, lastSeen: Date?,
                                            lastDropWasSleep: Bool = false, now: Date) -> [AlertFire] {
        let id = AlertRuleID.baglantiKoptu
        guard id.uygulanir(subject) else { return [] }
        let key = AlertKey(id, subject)
        let cfg = config.rule(id, subject)
        var st = states[key] ?? AlertState()
        guard cfg.on else {
            st.aktif = false; states[key] = st
            return []
        }
        guard let lastSeen else { return [] }
        let elapsed = now.timeIntervalSince(lastSeen)
        let cond = elapsed >= Double(cfg.esik) * 60 && !lastDropWasSleep
        let clear = elapsed < Double(cfg.esik) * 60
        let minutes = Int(elapsed / 60)
        var out: [AlertFire] = []
        if let text = step(&st, cond: cond, clear: clear, text: "\(minutes) dakikadır görülmedi.", now: now) {
            out.append(AlertFire(baslik: "\(deviceName): \(id.ad)", metin: text, ruleId: id, subject: subject))
        }
        states[key] = st
        return out
    }

    // MARK: Ic

    private struct Check { var cond: Bool; var clear: Bool; var text: String; var baslangic: Date? }

    /// nil: kural bu Snapshot'ta degerlendirilemez (alan yok).
    private func check(_ id: AlertRuleID, _ s: Snapshot, _ cfg: AlertRuleConfig, _ st: AlertState, _ now: Date) -> Check? {
        switch id {
        case .pilDusuk:
            guard let b = s.battery else { return nil }
            let cond = b.level <= cfg.esik && !b.charging
            let clear = b.level >= cfg.esik + 5 || b.charging
            return Check(cond: cond, clear: clear, text: "%\(b.level) kaldı, şarjda değil.", baslangic: nil)
        case .pilDoldu:
            guard let b = s.battery else { return nil }
            let cond = b.level >= cfg.esik && b.charging
            return Check(cond: cond, clear: !cond, text: "Pil %\(b.level), şarj tamamlandı.", baslangic: nil)
        case .diskDolu:
            guard let d = s.disk, d.total > 0 else { return nil }
            let pct = Double(d.used) / Double(d.total) * 100
            let free = d.total > d.used ? d.total - d.used : 0
            let gb = Int((Double(free) / 1_000_000_000).rounded())
            return Check(cond: pct >= Double(cfg.esik), clear: pct < Double(cfg.esik - 2),
                         text: "Disk %\(Int(pct.rounded())) dolu, \(gb) GB boş.", baslangic: nil)
        case .cpuYuksek:
            guard let c = s.cpu else { return nil }
            guard c.total >= cfg.esik else {
                return Check(cond: false, clear: c.total < cfg.esik - 10, text: "", baslangic: nil)
            }
            let start = st.kosulBaslangic ?? now
            let elapsed = now.timeIntervalSince(start)
            let cond = elapsed >= Double(cfg.sureDk) * 60
            let minutes = max(cfg.sureDk, Int(elapsed / 60))
            return Check(cond: cond, clear: false, text: "İşlemci \(minutes) dakikadır %\(c.total).", baslangic: start)
        case .bellekKritik:
            guard let p = s.mem?.pressure else { return nil }
            let cond = p == "critical"
            return Check(cond: cond, clear: !cond, text: "Bellek baskısı kritik.", baslangic: nil)
        case .sicak:
            if let t = s.battery?.temp {
                let txt = String(format: "%.1f", t).replacingOccurrences(of: ".", with: ",")
                return Check(cond: t >= Double(cfg.esik), clear: t < Double(cfg.esik - 2), text: "Pil \(txt)°C.", baslangic: nil)
            }
            if let th = s.thermal {
                let cond = th == "critical"
                return Check(cond: cond, clear: !cond, text: "Sıcaklık kritik.", baslangic: nil)
            }
            return nil
        case .baglantiKoptu:
            return nil
        }
    }

    /// Gecis + histerezis + soguma. Bildirim metni donerse atilir.
    private func step(_ st: inout AlertState, cond: Bool, clear: Bool, text: String, now: Date) -> String? {
        if st.aktif {
            if clear { st.aktif = false }
            return nil
        }
        guard cond else { return nil }
        st.aktif = true
        let t = Int(now.timeIntervalSince1970)
        if let son = st.son, Double(t - son) < Self.cooldown { return nil }
        st.son = t
        return text
    }
}
