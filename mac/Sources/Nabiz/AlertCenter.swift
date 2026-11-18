// Uyari merkezi: kural motoru (NabizCore.AlertEngine) + macOS bildirimleri. docs/uyarilar.md
import SwiftUI
import AppKit
import SystemConfiguration
import UserNotifications
import NabizCore

/// Bildirim gosterimi ve tiklama: uygulama on planda da afis cikar; tiklayinca uygulama one gelir.
final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }
    }
}

@MainActor @Observable
final class AlertCenter {
    static let shared = AlertCenter()

    /// Sistem bildirim izni; ayarlar satiri bunu gosterir.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var engine = AlertEngine()
    @ObservationIgnored private var persisted: [AlertKey: AlertState] = [:]
    @ObservationIgnored private let delegate = AlertNotificationDelegate()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    /// swift run gibi paketsiz calismada UNUserNotificationCenter coker.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        guard !started else { return }
        started = true
        loadStates()
        center?.delegate = delegate
        Task { await refreshAuthorization(requestIfNeeded: true) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in await AlertCenter.shared.refreshAuthorization(requestIfNeeded: false) }
        }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.checkConnection()
            }
        }
    }

    func refreshAuthorization(requestIfNeeded: Bool) async {
        guard let center else { return }
        var s = await center.notificationSettings().authorizationStatus
        if s == .notDetermined && requestIfNeeded {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                NSLog("Nabiz bildirim: requestAuthorization granted=%d", granted ? 1 : 0)
            } catch {
                NSLog("Nabiz bildirim: requestAuthorization hata: %@", String(describing: error))
            }
            s = await center.notificationSettings().authorizationStatus
        }
        NSLog("Nabiz bildirim: authorizationStatus=%ld bundle=%@", s.rawValue, Bundle.main.bundleIdentifier ?? "yok")
        authorization = s
    }

    func requestAuthorization() { Task { await refreshAuthorization(requestIfNeeded: true) } }

    // MARK: Veri girisi

    func macSnapshot(_ snap: Snapshot) {
        engine.config = Self.loadConfig()
        let fires = engine.evaluate(snapshot: snap, subject: .mac, deviceName: Self.macName(), now: Date())
        finish(fires)
    }

    func phoneSnapshot(_ snap: Snapshot, ready: Bool, name: String?) {
        engine.config = Self.loadConfig()
        let now = Date()
        let fires = engine.evaluate(snapshot: snap, subject: .telefon, deviceName: name ?? "Telefon", now: now,
                                    receivedAt: now, ready: ready)
        finish(fires)
    }

    private func checkConnection() {
        let phone = PhoneModel.shared
        engine.config = Self.loadConfig()
        let fires = engine.evaluateConnection(subject: .telefon, deviceName: phone.phoneName ?? phone.paired?.name ?? "Telefon",
                                              lastSeen: phone.lastSeen, now: Date())
        finish(fires)
    }

    func sendTest() {
        post(title: "Nabız: Deneme bildirimi", body: "Bildirimler çalışıyor.", id: "deneme")
    }

    // MARK: Ic

    private func finish(_ fires: [AlertFire]) {
        savePersisted()
        for f in fires { NSLog("Nabiz bildirim: kural tetiklendi %@", f.ruleId.rawValue); post(title: f.baslik, body: f.metin, id: "\(f.ruleId.rawValue).\(f.subject.rawValue)") }
    }

    private func post(title: String, body: String, id: String) {
        guard let center else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        center.add(UNNotificationRequest(identifier: "\(id).\(UUID().uuidString)", content: c, trigger: nil)) { error in
            NSLog("Nabiz bildirim: gonderildi id=%@ hata=%@", id, error.map { String(describing: $0) } ?? "yok")
        }
    }

    private static func macName() -> String { (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac" }

    private static func loadConfig() -> AlertConfig {
        let d = UserDefaults.standard
        var cfg = AlertConfig()
        for s in AlertSubject.allCases {
            for id in AlertRuleID.allCases where id.uygulanir(s) {
                let k = AlertKey(id, s)
                cfg.rules[k] = AlertRuleConfig(on: d.object(forKey: "\(k.prefix).on") as? Bool ?? id.varsayilanAcik(s),
                                               esik: d.object(forKey: "\(k.prefix).esik") as? Int ?? id.esikVarsayilan,
                                               sureDk: d.object(forKey: "\(k.prefix).sureDk") as? Int ?? id.sureVarsayilan)
            }
        }
        return cfg
    }

    /// Soguma icin `son` kalicidir. `aktif` yazilir ama acilista okunmaz: ilk ornekte kosul dogruysa bildirim atilir.
    private func loadStates() {
        let d = UserDefaults.standard
        for s in AlertSubject.allCases {
            for id in AlertRuleID.allCases where id.uygulanir(s) {
                let k = AlertKey(id, s)
                if let son = d.object(forKey: "\(k.prefix).son") as? Int {
                    engine.states[k] = AlertState(aktif: false, son: son)
                }
            }
        }
        persisted = engine.states
    }

    private func savePersisted() {
        let d = UserDefaults.standard
        for (k, st) in engine.states where persisted[k]?.aktif != st.aktif || persisted[k]?.son != st.son {
            d.set(st.aktif, forKey: "\(k.prefix).aktif")
            if let son = st.son { d.set(son, forKey: "\(k.prefix).son") }
        }
        persisted = engine.states
    }
}
