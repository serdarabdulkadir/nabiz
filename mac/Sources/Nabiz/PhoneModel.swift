// Telefon kanali modeli: oturum yasam dongusu, SAS, telefonun Snapshot'i, telefondan gelen komutlar.
// Protokol: docs/protokol.md (PeerSession aga bagli olmayan durum makinesidir; baytlar PeerServer'dan gelir).
import SwiftUI
import SystemConfiguration
import NabizCore

enum PhoneLink: Equatable {
    case dinliyor            // baglanti yok
    case elSikisma           // baglandi, el sikisma suruyor
    case sasBekliyor
    case bagli
}

@MainActor @Observable
final class PhoneModel {
    static let shared = PhoneModel()

    private(set) var link: PhoneLink = .dinliyor
    private(set) var sas: String?
    private(set) var listenError: String?
    private(set) var lastError: String?
    private(set) var paired: PairedPhone?
    private(set) var phoneName: String?
    private(set) var phoneModel: String?
    private(set) var snapshot: Snapshot?
    private(set) var lastSeen: Date?
    /// Son 5 RTT olcumunun ortancasi (ms); olcum yoksa nil.
    private(set) var latencyMs: Int?

    // Telefon verisi (bolum 10): yalniz bellekte; baglanti kopunca / izin kapaninca silinir.
    private(set) var perm = PermState()
    private(set) var callState = CallState(durum: .bosta)
    private(set) var callStartedAt: Date?
    private(set) var feed = NotificationFeed()
    private(set) var contacts = ContactsIndex()
    private(set) var contactBook: [ContactRecord] = []
    private(set) var contactsTotal: Int?
    private(set) var contactsLoading = false
    private(set) var callLog: [CallLogEntry]?
    private(set) var callLogLoading = false
    /// Son yanit sonucu (anahtar -> sonuc); yeni yanitta silinir.
    private(set) var replyResults: [String: NotifResult] = [:]
    private var icons: [String: NSImage] = [:]   // paket -> ikon (bellek)

    var notifications: [PhoneNotification] { feed.items }
    func icon(for paket: String) -> NSImage? { icons[paket] }
    func contact(for number: String?) -> ContactRecord? { contacts.match(number: number) }

    @ObservationIgnored private let store = PeerStore()
    @ObservationIgnored private let server = PeerServer()
    @ObservationIgnored private let discovery = DiscoveryResponder()
    @ObservationIgnored private var sessions: [Int: PeerSession] = [:]   // baglanti kimligi -> oturum (aktif + aday)
    @ObservationIgnored private var openedAts: [Int: Date] = [:]
    @ObservationIgnored private var sasSinces: [Int: Date] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var housekeeping: Task<Void, Never>?
    @ObservationIgnored private var interval = 10
    @ObservationIgnored private var lastReceived = Date()
    @ObservationIgnored private var lastSent = Date()
    @ObservationIgnored private var rtt = RTTTracker()
    @ObservationIgnored private var lastPing = Date()
    @ObservationIgnored private var requestId = 100
    @ObservationIgnored private var repliedAt: [String: Date] = [:]   // Mac'ten yanitlanan anahtar -> an (banner bastirma)
    @ObservationIgnored private var contactsLoaded = false
    @ObservationIgnored private var contactsDirty = false
    @ObservationIgnored private var callLogLoaded = false
    @ObservationIgnored private var callLogDirty = false
    private static let contactPageSize = 40, callLogPageSize = 100, callLogLimit = 300

    var isConnected: Bool { link == .bagli }

    func start() {
        guard !started else { return }
        started = true
        paired = store.pairedPhone()
        server.onOpen = { [weak self] id in self?.opened(id) }
        server.onData = { [weak self] id, data in self?.received(id, data) }
        server.onClose = { [weak self] id, wasActive in self?.closed(id, wasActive: wasActive) }
        server.onListenState = { [weak self] err in self?.listenError = err }
        let mon = MacStateMonitor.shared
        mon.onChange = { [weak self] k, e, u in self?.sendMacState(k, e, u) }
        mon.start()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CallBubbleController.shared.update() }
        }
        startHousekeeping()
        server.start(name: Self.computerName(), deviceId: store.deviceId())
        let srv = server
        discovery.start(deviceId: store.deviceId(), name: Self.computerName()) { srv.tcpPort }
    }

    // MARK: Disaridan cagrilar

    func confirmSAS(accepted: Bool) {
        guard link == .sasBekliyor, let cid = server.slots.candidate, var s = sessions[cid] else { return }
        let out = s.confirmSAS(accepted: accepted)
        sessions[cid] = s
        apply(out, from: cid)
    }

    /// Eslesmeyi unut: pin silinir, baglanti kapanir.
    func forget() {
        store.forgetPairedPhone()
        paired = nil
        lastError = nil
        server.closeAll()
    }

    /// Mac paneli acildi/kapandi: telefona yeni `sub` gonderilir (2 sn / 10 sn).
    func panelOpenChanged(_ open: Bool) {
        guard link == .bagli else { return }
        send(.sub(aralikSn: open ? 2 : 10))
    }

    // MARK: Baglanti

    private func opened(_ id: Int) {
        let model = [SystemInfo.modelName(), SystemInfo.chipName()].compactMap { $0 }
        let hello = PeerHello(ad: Self.computerName(), surum: Self.appVersion, cihazId: store.deviceId(), platform: "mac",
                              model: model.isEmpty ? nil : (model.count == 2 ? "\(model[0]) (\(model[1]))" : model[0]))
        var s = PeerSession(role: .mac, identity: store.identity(), hello: hello, pinnedPeerKey: store.pairedPhone()?.key)
        let out = s.start()
        sessions[id] = s
        openedAts[id] = Date()
        if server.slots.active == nil { lastError = nil }
        refreshLink()
        apply(out, from: id)
    }

    private func received(_ id: Int, _ data: Data) {
        guard var s = sessions[id] else { return }
        if id == server.slots.active { lastReceived = Date() }
        let out = s.receive(data)
        sessions[id] = s
        apply(out, from: id)
    }

    private func closed(_ id: Int, wasActive: Bool) {
        sessions[id] = nil; openedAts[id] = nil; sasSinces[id] = nil
        if wasActive { endActiveSession() }
        refreshLink()
    }

    /// Aktif oturum bitti (kapandi ya da yenisi devraldi): eski veri yaniltmasin, karolar gosterilmez; son gorulme kalir.
    private func endActiveSession() {
        statsTask?.cancel(); statsTask = nil
        snapshot = nil
        rtt.reset(); latencyMs = nil
        clearPhoneData()
    }

    /// Gorunen baglanti durumu: aktif varsa bagli, yoksa adayin el sikisma / SAS asamasi, yoksa dinliyor.
    private func refreshLink() {
        if server.slots.active != nil {
            link = .bagli
        } else if let c = server.slots.candidate, let s = sessions[c] {
            link = s.state == .sasBekliyor ? .sasBekliyor : .elSikisma
        } else {
            link = .dinliyor
        }
        if link != .sasBekliyor { sas = nil; SASPrompt.hide() }
    }

    private func apply(_ out: PeerSessionOutput, from id: Int) {
        for f in out.frames { server.send(f, to: id); if id == server.slots.active { lastSent = Date() } }
        for e in out.events { handle(e, from: id) }
    }

    private func handle(_ event: PeerSessionEvent, from id: Int) {
        switch event {
        case .sasGerekli(let code, _):
            sas = code; sasSinces[id] = Date(); SASPrompt.show(code: code)
            refreshLink()
        case .kuruldu(let key, let name):
            // Aday dogrulandi: eski oturum (varsa) kapanir, aday aktif olur.
            let r = server.promote(id)
            guard r.promoted else { server.close(id); return }
            if let old = r.replaced { sessions[old] = nil; openedAts[old] = nil; sasSinces[old] = nil; endActiveSession() }
            lastReceived = Date(); lastSent = Date(); lastError = nil
            interval = 10
            rtt.reset(); latencyMs = nil
            refreshLink()
            if store.pairedPhone()?.key != key { store.savePairedPhone(PairedPhone(key: key, name: name, model: nil)) }
            paired = store.pairedPhone()
            phoneName = name
            lastSeen = Date()
            send(.sub(aralikSn: MonitorModel.shared.panelOpen ? 2 : 10))
            sendStats(id: nil)
            sendMacState(MacStateMonitor.shared.locked, MacStateMonitor.shared.screenOff, false)
            sendPing()
            restartStatsLoop()
        case .mesaj(let env):
            guard id == server.slots.active else { return }
            handle(env)
        case .bilinmeyenTip:
            guard id == server.slots.active else { return }
            send(.error(PeerError(kod: "bilinmeyen_tip")))
        case .kapandi(let err):
            if let text = Self.describe(err) { lastError = text }
            server.close(id)
        }
    }

    private func handle(_ env: PeerEnvelope) {
        lastSeen = Date()
        switch env.message {
        case .hello(let h):
            phoneName = h.ad; phoneModel = h.model
            if var p = store.pairedPhone() {
                p.name = h.ad; p.model = h.model
                store.savePairedPhone(p); paired = p
            }
        case .ping: send(.pong, id: env.id)
        case .pong:
            if rtt.pongReceived(id: env.id, at: ProcessInfo.processInfo.systemUptime) != nil { latencyMs = rtt.medianMs }
        case .cmdResult, .macState: break
        case .error(let e):
            // Izin yokken istek islenmez: bekleyen yukleme bayragi takili kalmasin.
            guard e.kod == "izin_yok" else { break }
            if e.mesaj == "kisiler" { contactsLoading = false; contactsDirty = false }
            if e.mesaj == "aramaGecmisi" { callLogLoading = false; callLogDirty = false }
        case .permState(let p): applyPerm(p)
        case .callState(let new):
            updateCallClock(old: callState, new: new)
            callState = new
            CallBubbleController.shared.update()
        case .contactsPage(let page): applyContactsPage(page)
        case .contactsChanged: if perm.kisiler { requestContacts(restart: true) }
        case .callLogPage(let page): applyCallLogPage(page)
        case .callLogChanged: if perm.aramaGecmisi { requestCallLog(restart: true) }
        case .notifList(let list):
            guard perm.bildirimler else { break }
            list.forEach(cacheIcon)
            feed.replace(with: list)
        case .notifPosted(let n):
            guard perm.bildirimler else { break }
            cacheIcon(n)
            let changed = feed.posted(n)
            let recentlyReplied = repliedAt[n.anahtar].map { Date().timeIntervalSince($0) < 10 } ?? false
            if changed && !recentlyReplied { AlertCenter.shared.phoneNotification(n) }
        case .notifRemoved(let key):
            feed.removed(key)
            AlertCenter.shared.removePhoneNotifications(keys: [key])
        case .notifResult(let key, let result): replyResults[key] = result
        case .callAnswer, .callReject, .callHangup, .callDial, .contactsSync, .callLogSync,
             .notifDismiss, .notifClear, .notifReply: break   // mac->tel yonu; telefondan gelmez
        case .stats(let s):
            snapshot = s
            AlertCenter.shared.phoneSnapshot(s, ready: link == .bagli, name: phoneName ?? paired?.name)
        case .sub(let n):
            interval = n
            restartStatsLoop()
            sendStats(id: nil)
        case .cmd(let action): runCommand(action, id: env.id)
        }
    }

    // MARK: Telefon verisi

    private func nextId() -> Int { requestId += 1; return requestId }

    private func clearPhoneData() {
        perm = PermState()
        callState = CallState(durum: .bosta); callStartedAt = nil
        feed.clear(); icons = [:]; replyResults = [:]; repliedAt = [:]
        clearContacts(); clearCallLog()
        AlertCenter.shared.removePhoneNotifications(keys: nil)
        CallBubbleController.shared.update()
    }

    private func clearContacts() {
        contacts.reset(); contactBook = []; contactsTotal = nil
        contactsLoading = false; contactsLoaded = false; contactsDirty = false
    }

    private func clearCallLog() {
        callLog = nil; callLogLoading = false; callLogLoaded = false; callLogDirty = false
    }

    private func applyPerm(_ p: PermState) {
        perm = p
        if !p.bildirimler {
            feed.clear(); icons = [:]; replyResults = [:]
            AlertCenter.shared.removePhoneNotifications(keys: nil)
        }
        if !p.kisiler { clearContacts() } else if !contactsLoaded && !contactsLoading { requestContacts(from: 0) }
        if !p.aramaGecmisi { clearCallLog() } else if !callLogLoaded && !callLogLoading { requestCallLog(from: 0) }
        CallBubbleController.shared.update()
    }

    private func cacheIcon(_ n: PhoneNotification) {
        guard icons[n.paket] == nil, let b64 = n.ikon, let data = Data(base64Encoded: b64),
              let img = NSImage(data: data) else { return }
        icons[n.paket] = img
    }

    /// `restart`: degisiklik bildirimi; sayfalar akiyorsa bitince bastan tekrar istenir.
    private func requestContacts(from offset: Int = 0, restart: Bool = false) {
        if restart && contactsLoading { contactsDirty = true; return }
        contactsLoading = true
        send(.contactsSync(ContactsSync(ofset: offset, adet: Self.contactPageSize)), id: nextId())
    }

    private func requestCallLog(from offset: Int = 0, restart: Bool = false) {
        if restart && callLogLoading { callLogDirty = true; return }
        callLogLoading = true
        send(.callLogSync(CallLogSync(ofset: offset, adet: Self.callLogPageSize)), id: nextId())
    }

    private func applyContactsPage(_ page: ContactsPage) {
        guard perm.kisiler else { return }
        if page.ofset == 0 { contactBook = []; contacts.reset() }
        guard page.ofset == contactBook.count else { contactsLoading = false; contactsDirty = false; return }   // sira disi sayfa
        contactBook.append(contentsOf: page.kisiler)
        contacts.sync(with: contactBook)
        contactsTotal = page.toplam
        if page.son || page.kisiler.isEmpty || contactBook.count >= page.toplam {
            contactsLoaded = true; contactsLoading = false
            if contactsDirty { contactsDirty = false; requestContacts(from: 0) }
        } else {
            requestContacts(from: contactBook.count)
        }
    }

    private func applyCallLogPage(_ page: CallLogPage) {
        guard perm.aramaGecmisi else { return }
        var log = page.ofset == 0 ? [] : (callLog ?? [])
        guard page.ofset == log.count else { callLogLoading = false; callLogDirty = false; return }
        log.append(contentsOf: page.kayitlar)
        callLog = log
        if page.son || page.kayitlar.isEmpty || log.count >= Self.callLogLimit {
            callLogLoaded = true; callLogLoading = false
            if callLogDirty { callLogDirty = false; requestCallLog(from: 0) }
        } else {
            requestCallLog(from: log.count)
        }
    }

    private func updateCallClock(old: CallState, new: CallState) {
        guard new.durum == .acik else { callStartedAt = nil; return }
        if let s = new.sureSn { callStartedAt = Date().addingTimeInterval(-TimeInterval(s)) }
        else if old.durum != .acik || callStartedAt == nil { callStartedAt = Date() }
    }

    // Eylemler (izin yoksa telefon `izin_yok` doner; Mac hic gondermez).
    func answer() { if perm.cagriYonetimi { send(.callAnswer, id: nextId()) } }
    func reject() { if perm.cagriYonetimi { send(.callReject, id: nextId()) } }
    func hangup() { if perm.cagriYonetimi { send(.callHangup, id: nextId()) } }

    /// Yalniz tus karakterleri (0-9 + * #) gonderilir.
    func dial(_ raw: String) {
        let number = ContactText.dialable(raw)
        guard perm.cagriYonetimi, !number.isEmpty else { return }
        send(.callDial(numara: number), id: nextId())
    }

    func dismiss(_ key: String) { if perm.bildirimler { send(.notifDismiss(anahtar: key), id: nextId()) } }
    func clearAll() { if perm.bildirimler { send(.notifClear, id: nextId()) } }

    func reply(_ key: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard perm.bildirimler, !t.isEmpty else { return }
        replyResults[key] = nil
        repliedAt[key] = Date()
        send(.notifReply(anahtar: key, metin: t), id: nextId())
    }

    // MARK: Gonderim

    private func send(_ message: PeerMessage, id: Int? = nil) {
        guard let aid = server.slots.active, var s = sessions[aid] else { return }
        do {
            let frame = try s.send(PeerEnvelope(message, id: id))
            sessions[aid] = s
            server.send(frame, to: aid); lastSent = Date()
        } catch {
            server.close(aid)
        }
    }

    private func sendMacState(_ locked: Bool, _ screenOff: Bool, _ sleeping: Bool) {
        guard link == .bagli else { return }
        send(.macState(kilitli: locked, ekranKapali: screenOff, uykuyaGidiyor: sleeping))
    }

    private func sendStats(id: Int?) {
        guard let snap = MonitorModel.shared.snapshot else { return }
        send(.stats(snap), id: id)
    }

    private func restartStatsLoop() {
        statsTask?.cancel()
        let secs = max(1, interval)
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(secs))
                if Task.isCancelled { break }
                self?.sendStats(id: nil)
            }
        }
    }

    /// Aday: el sikisma 10 sn, SAS onayi 60 sn zaman asimi. Aktif: ping 15 sn, 45 sn sessizlikte kapat.
    private func startHousekeeping() {
        housekeeping?.cancel()
        housekeeping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        for (id, s) in Array(sessions) where id != server.slots.active {
            if s.state == .elSikismaBekliyor, now.timeIntervalSince(openedAts[id] ?? now) > ConnectionSlots.candidateTimeout {
                lastError = "El sıkışma zaman aşımı"; server.close(id)
            } else if s.state == .sasBekliyor, now.timeIntervalSince(sasSinces[id] ?? now) > 60 {
                lastError = "Eşleşme onayı zaman aşımı"; server.close(id)
            }
        }
        if let aid = server.slots.active {
            if now.timeIntervalSince(lastReceived) > 45 { lastError = "Telefondan yanıt yok"; server.close(aid); return }
            if now.timeIntervalSince(lastPing) >= 15 { sendPing() }
        }
    }

    private func sendPing() {
        lastPing = Date()
        send(.ping, id: rtt.pingSent(at: ProcessInfo.processInfo.systemUptime))
    }

    // MARK: Komutlar

    private func runCommand(_ action: PeerCommand, id: Int?) {
        let defaults = UserDefaults.standard
        func enabled(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        switch action {
        case .yenile:
            guard enabled(SettingsKey.cmdRefresh, true) else { return reply(action, .kapali, id) }
            Task { [weak self] in
                let snap = await MonitorModel.shared.refreshNow()
                self?.send(.stats(snap), id: id)
                self?.reply(action, .tamam, id)
            }
        case .kilitle:
            guard enabled(SettingsKey.cmdLock, false) else { return reply(action, .kapali, id) }
            if MacStateMonitor.shared.locked { return reply(action, .tamam, id) }   // zaten kilitli: tekrar kilitleme
            let cg = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
            let (path, args) = FileManager.default.isExecutableFile(atPath: cg)
                ? (cg, ["-suspend"]) : ("/usr/bin/pmset", ["displaysleepnow"])
            run(path, args, action, id)
        case .uyandir:
            guard enabled(SettingsKey.cmdWake, true) else { return reply(action, .kapali, id) }
            run("/usr/bin/caffeinate", ["-u", "-t", "3"], action, id)
        case .uyut:
            guard enabled(SettingsKey.cmdSleep, false) else { return reply(action, .kapali, id) }
            run("/usr/bin/pmset", ["sleepnow"], action, id)
        }
    }

    private func reply(_ action: PeerCommand, _ result: PeerCommandResult, _ id: Int?) {
        send(.cmdResult(eylem: action, sonuc: result), id: id)
    }

    private func run(_ path: String, _ args: [String], _ action: PeerCommand, _ id: Int?) {
        Task { [weak self] in
            let ok = await Task.detached { () -> Bool in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { return false }
                p.waitUntilExit()
                return p.terminationStatus == 0
            }.value
            self?.reply(action, ok ? .tamam : .hata, id)
        }
    }

    // MARK: Yardimcilar

    private static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1"
    }

    private static func describe(_ e: PeerSessionError) -> String? {
        switch e {
        case .anahtarUyusmuyor: "Eşleşme anahtarı değişti. Önce eşleşmeyi unutup yeniden eşleştir."
        case .sasReddedildi: nil
        case .surumUyusmuyor: e.surumMetni
        default: "Bağlantı kapandı (\(e))."
        }
    }
}
