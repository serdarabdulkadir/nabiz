// Uyari merkezi: kural motoru (NabizCore.AlertEngine) + macOS bildirimleri. docs/uyarilar.md
import SwiftUI
import AppKit
import SystemConfiguration
import UserNotifications
import NabizCore

/// Bildirim gosterimi ve tiklama: uygulama on planda da afis cikar; tiklayinca uygulama one gelir.
/// Telefon bildirimi kategori / eylem / kimlik on ekleri (uyari kurali kimlikleriyle cakismaz).
enum PhoneNotifID {
    static let prefix = "nabiz.tel."
    static let reply = "nabiz.tel.eylem.yanitla"
    static let dismiss = "nabiz.tel.eylem.kapat"
    static let catReplyDismiss = "nabiz.tel.kat.yanit-kapat"
    static let catReply = "nabiz.tel.kat.yanit"
    static let catDismiss = "nabiz.tel.kat.kapat"
}

/// Aktar teklif bildirimi: kategori ve eylem kimlikleri.
enum AktarNotifID {
    static let prefix = "nabiz.aktar."
    static let category = "nabiz.aktar.kat.teklif"
    static let accept = "nabiz.aktar.eylem.kabul"
    static let reject = "nabiz.aktar.eylem.red"
}

final class AlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .list, .sound] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let key = response.notification.request.content.userInfo["anahtar"] as? String
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let aid = response.notification.request.content.userInfo["aid"] as? String
        await MainActor.run {
            switch action {
            case AktarNotifID.accept:
                if let aid { AktarModel.shared.respond(aid, accept: true) }
            case AktarNotifID.reject:
                if let aid { AktarModel.shared.respond(aid, accept: false) }
            case PhoneNotifID.reply:
                if let key, let text { PhoneModel.shared.reply(key, text) }
            case PhoneNotifID.dismiss:
                if let key { PhoneModel.shared.dismiss(key) }
            default:
                NSApp.activate(ignoringOtherApps: true)
                if key != nil { PhoneWindow.show(.bildirimler) }
            }
        }
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
        center?.setNotificationCategories(Self.phoneCategories().union(Self.aktarCategories()))
        Task {
            await refreshAuthorization(requestIfNeeded: true)
            // Reddedilmisse macOS yeniden sormaz: acilista kendi penceremizle Sistem Ayarlari'na yonlendir.
            if authorization == .denied { NotifPrompt.showIfNeeded() }
        }
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
        if s == .authorized || s == .provisional { NotifPrompt.hide() }
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

    // MARK: Telefon bildirimleri

    private static func phoneCategories() -> Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(identifier: PhoneNotifID.reply, title: "Yanıtla", options: [],
                                                  textInputButtonTitle: "Gönder", textInputPlaceholder: "Yanıt yaz")
        let dismiss = UNNotificationAction(identifier: PhoneNotifID.dismiss, title: "Telefonda kapat", options: [])
        return [
            UNNotificationCategory(identifier: PhoneNotifID.catReplyDismiss, actions: [reply, dismiss], intentIdentifiers: [],
                                 hiddenPreviewsBodyPlaceholder: "Yeni bildirim", options: []),
            UNNotificationCategory(identifier: PhoneNotifID.catReply, actions: [reply], intentIdentifiers: [],
                                 hiddenPreviewsBodyPlaceholder: "Yeni bildirim", options: []),
            UNNotificationCategory(identifier: PhoneNotifID.catDismiss, actions: [dismiss], intentIdentifiers: [],
                                 hiddenPreviewsBodyPlaceholder: "Yeni bildirim", options: []),
        ]
    }

    /// Yeni telefon bildirimi: "Uygulama · Baslik" / metin. Ayarlardan kapatilabilir.
    func phoneNotification(_ n: PhoneNotification) {
        guard UserDefaults.standard.object(forKey: SettingsKey.phoneNotifMac) as? Bool ?? true, let center else { return }
        guard n.baslik?.isEmpty == false || n.metin?.isEmpty == false else { return }
        let c = UNMutableNotificationContent()
        c.threadIdentifier = n.paket
        c.userInfo = ["anahtar": n.anahtar]
        // Gizlilik: Mac kilitli ya da ekran kapaliyken icerik gosterilmez, eylem eklenmez.
        let mon = MacStateMonitor.shared
        if mon.locked || mon.screenOff {
            c.title = "\(n.uygulama) · Yeni bildirim"
            center.add(UNNotificationRequest(identifier: PhoneNotifID.prefix + n.anahtar, content: c, trigger: nil))
            return
        }
        c.title = [n.uygulama, n.baslik].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        c.body = n.metin ?? ""
        switch (n.yanitlanabilir, n.kapatilabilir) {
        case (true, true): c.categoryIdentifier = PhoneNotifID.catReplyDismiss
        case (true, false): c.categoryIdentifier = PhoneNotifID.catReply
        case (false, true): c.categoryIdentifier = PhoneNotifID.catDismiss
        case (false, false): break
        }
        center.add(UNNotificationRequest(identifier: PhoneNotifID.prefix + n.anahtar, content: c, trigger: nil))
    }

    /// Telefonda kapanan bildirimin Mac'teki kopyasini kaldirir; `keys == nil` hepsini.
    func removePhoneNotifications(keys: [String]?) {
        guard let center else { return }
        if let keys {
            center.removeDeliveredNotifications(withIdentifiers: keys.map { PhoneNotifID.prefix + $0 })
        } else {
            center.getDeliveredNotifications { list in
                let ids = list.map(\.request.identifier).filter { $0.hasPrefix(PhoneNotifID.prefix) }
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }

    // MARK: Aktar bildirimleri (kimlik oneki nabiz.aktar.*)

    private static func aktarCategories() -> Set<UNNotificationCategory> {
        let accept = UNNotificationAction(identifier: AktarNotifID.accept, title: "Kabul et", options: [])
        let reject = UNNotificationAction(identifier: AktarNotifID.reject, title: "Reddet", options: [])
        return [UNNotificationCategory(identifier: AktarNotifID.category, actions: [accept, reject], intentIdentifiers: [],
                                       options: [])]
    }

    /// "Redmi Note 13 Pro 3 fotograf gondermek istiyor" + Kabul et / Reddet.
    func aktarOffer(aid: String, body: String) {
        guard let center else { return }
        let c = UNMutableNotificationContent()
        c.title = "Nabız Aktar"
        c.body = body
        c.sound = .default
        c.categoryIdentifier = AktarNotifID.category
        c.userInfo = ["aid": aid]
        center.add(UNNotificationRequest(identifier: AktarNotifID.prefix + aid, content: c, trigger: nil))
    }

    func aktarRemoveOffer(aid: String) {
        guard let center else { return }
        center.removeDeliveredNotifications(withIdentifiers: [AktarNotifID.prefix + aid])
        center.removePendingNotificationRequests(withIdentifiers: [AktarNotifID.prefix + aid])
    }

    func aktarInfo(title: String, body: String) {
        guard let center else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        center.add(UNNotificationRequest(identifier: AktarNotifID.prefix + "bilgi." + UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: AI limit bildirimleri (kimlik oneki nabiz.ai.*)

    func aiNotify(id: String, title: String, body: String) {
        guard let center else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        center.add(UNNotificationRequest(identifier: "nabiz.ai.\(id)", content: c, trigger: nil))
    }

    /// `after` sn sonra gosterilir (ayni kimlikle yeniden kurulursa onceki yerine gecer).
    func aiSchedule(id: String, title: String, body: String, after seconds: TimeInterval) {
        guard let center, seconds > 0 else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        center.add(UNNotificationRequest(identifier: "nabiz.ai.\(id)", content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    func aiCancelPending(ids: [String]) {
        center?.removePendingNotificationRequests(withIdentifiers: ids.map { "nabiz.ai.\($0)" })
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
