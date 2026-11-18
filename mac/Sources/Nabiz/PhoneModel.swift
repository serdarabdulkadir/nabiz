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

    @ObservationIgnored private let store = PeerStore()
    @ObservationIgnored private let server = PeerServer()
    @ObservationIgnored private var session: PeerSession?
    @ObservationIgnored private var linkId: Int?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var housekeeping: Task<Void, Never>?
    @ObservationIgnored private var interval = 10
    @ObservationIgnored private var lastReceived = Date()
    @ObservationIgnored private var lastSent = Date()
    @ObservationIgnored private var openedAt = Date()
    @ObservationIgnored private var sasSince = Date()
    @ObservationIgnored private var rtt = RTTTracker()
    @ObservationIgnored private var lastPing = Date()

    var isConnected: Bool { link == .bagli }

    func start() {
        guard !started else { return }
        started = true
        paired = store.pairedPhone()
        server.onOpen = { [weak self] id in self?.opened(id) }
        server.onData = { [weak self] id, data in self?.received(id, data) }
        server.onClose = { [weak self] id in self?.closed(id) }
        server.onListenState = { [weak self] err in self?.listenError = err }
        let mon = MacStateMonitor.shared
        mon.onChange = { [weak self] k, e, u in self?.sendMacState(k, e, u) }
        mon.start()
        server.start(name: Self.computerName(), deviceId: store.deviceId())
    }

    // MARK: Disaridan cagrilar

    func confirmSAS(accepted: Bool) {
        guard link == .sasBekliyor, var s = session else { return }
        let out = s.confirmSAS(accepted: accepted)
        session = s
        apply(out)
    }

    /// Eslesmeyi unut: pin silinir, baglanti kapanir.
    func forget() {
        store.forgetPairedPhone()
        paired = nil
        lastError = nil
        server.closeActive()
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
        session = s
        linkId = id
        link = .elSikisma
        lastError = nil
        sas = nil; SASPrompt.hide()
        openedAt = Date(); lastReceived = Date(); lastSent = Date()
        interval = 10
        rtt.reset(); latencyMs = nil
        apply(out)
        startHousekeeping()
    }

    private func received(_ id: Int, _ data: Data) {
        guard id == linkId, var s = session else { return }
        lastReceived = Date()
        let out = s.receive(data)
        session = s
        apply(out)
    }

    private func closed(_ id: Int) {
        guard id == linkId else { return }
        statsTask?.cancel(); housekeeping?.cancel()
        statsTask = nil; housekeeping = nil
        session = nil; linkId = nil
        link = .dinliyor
        sas = nil; SASPrompt.hide()
        // Eski veri yaniltmasin: bagli degilken karolar gosterilmez, ama son gorulme kalir.
        snapshot = nil
        rtt.reset(); latencyMs = nil
    }

    private func apply(_ out: PeerSessionOutput) {
        for f in out.frames { server.send(f); lastSent = Date() }
        for e in out.events { handle(e) }
    }

    private func handle(_ event: PeerSessionEvent) {
        switch event {
        case .sasGerekli(let code, _):
            sas = code; sasSince = Date(); link = .sasBekliyor; SASPrompt.show(code: code)
        case .kuruldu(let key, let name):
            sas = nil; SASPrompt.hide()
            link = .bagli
            if store.pairedPhone()?.key != key { store.savePairedPhone(PairedPhone(key: key, name: name, model: nil)) }
            paired = store.pairedPhone()
            phoneName = name
            lastSeen = Date()
            send(.sub(aralikSn: MonitorModel.shared.panelOpen ? 2 : 10))
            sendStats(id: nil)
            sendMacState(MacStateMonitor.shared.locked, MacStateMonitor.shared.screenOff, false)
            sendPing()
            restartStatsLoop()
        case .mesaj(let env): handle(env)
        case .bilinmeyenTip:
            send(.error(PeerError(kod: "bilinmeyen_tip")))
        case .kapandi(let err):
            if let text = Self.describe(err) { lastError = text }
            server.closeActive()
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
        case .cmdResult, .error, .macState: break
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

    // MARK: Gonderim

    private func send(_ message: PeerMessage, id: Int? = nil) {
        guard var s = session else { return }
        do {
            let frame = try s.send(PeerEnvelope(message, id: id))
            session = s
            server.send(frame); lastSent = Date()
        } catch {
            server.closeActive()
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

    /// ping 15 sn, 45 sn sessizlikte kapat; el sikisma 10 sn, SAS onayi 60 sn zaman asimi.
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
        switch link {
        case .elSikisma:
            if now.timeIntervalSince(openedAt) > 10 { lastError = "El sıkışma zaman aşımı"; server.closeActive() }
        case .sasBekliyor:
            if now.timeIntervalSince(sasSince) > 60 { lastError = "Eşleşme onayı zaman aşımı"; server.closeActive() }
        case .bagli:
            if now.timeIntervalSince(lastReceived) > 45 { lastError = "Telefondan yanıt yok"; server.closeActive(); return }
            if now.timeIntervalSince(lastPing) >= 15 { sendPing() }
        case .dinliyor: break
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
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
