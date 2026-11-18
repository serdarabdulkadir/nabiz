// Olcum dongusu: panel acikken yenileme hizi (varsayilan 2 sn), kapaliyken 5 sn. Ornekleme actor icinde.
import SwiftUI
import NabizCore

@MainActor @Observable
final class MonitorModel {
    static let shared = MonitorModel()
    static let closedInterval: Double = 5

    private(set) var snapshot: Snapshot?
    /// Son 30 CPU degeri (menu cubugu grafik stili).
    private(set) var cpuHistory = RingBuffer<Int>(capacity: 30)
    /// Son 10 dk (zaman damgali; panel kapaliyken de dolar).
    private(set) var history = History<HistoryPoint>(capacity: 700)
    static let historySeconds: Double = 600
    /// Mac'e ozel ek olcumler: yalniz panel acikken yenilenir.
    private(set) var extras = MacExtras()
    private(set) var devices: [DeviceBattery] = []
    let modelName = SystemInfo.modelName()
    let chipName = SystemInfo.chipName()

    var panelOpen = false {
        didSet { if oldValue != panelOpen { restart(); PhoneModel.shared.panelOpenChanged(panelOpen) } }
    }

    private let sampler = Sampler()
    private let extrasSampler = ExtrasSampler()
    private let deviceSampler = DeviceSampler()
    private var deviceTask: Task<Void, Never>?

    /// Telefondan gelen `yenile` komutu: anlik olcum al ve modele yaz.
    func refreshNow() async -> Snapshot {
        let snap = await sampler.sample()
        publish(snap)
        return snap
    }
    private var loop: Task<Void, Never>?

    private func publish(_ snap: Snapshot) {
        snapshot = snap
        if let c = snap.cpu?.total { cpuHistory.append(c) }
        history.append(HistoryPoint(snapshot: snap))
        history.removeOldest { $0.ts < Double(snap.ts) - Self.historySeconds }
        AlertCenter.shared.macSnapshot(snap)
    }

    /// Surec, sicaklik/fan ve cihaz pilleri; ilgili bolum kapaliysa olculmez.
    private func refreshExtras() async {
        let wantProc = PanelModule.processes.isOn, wantSensors = PanelModule.sensors.isOn
        if wantProc || wantSensors {
            let e = await extrasSampler.sample(processes: wantProc, sensors: wantSensors)
            if !Task.isCancelled { extras = e }
        }
        if PanelModule.devices.isOn {
            if deviceTask == nil {
                // Profiler yavas olabilir: dongu beklemez; DeviceSampler kendi 60 sn araligini uygular.
                deviceTask = Task { [deviceSampler] in
                    let d = await deviceSampler.read()
                    self.devices = d
                    self.deviceTask = nil
                }
            }
        } else if !devices.isEmpty {
            devices = []
        }
    }

    func start() {
        guard loop == nil else { return }
        restart()
    }

    /// Ayarlardan yenileme hizi degisince de cagrilir.
    func restart() {
        loop?.cancel()
        let open = panelOpen
        let configured = UserDefaults.standard.double(forKey: SettingsKey.refresh)
        let interval = open ? (configured > 0 ? configured : 2) : Self.closedInterval
        loop = Task { [sampler] in
            // Ilk fark icin bir on ornek al.
            if self.snapshot == nil {
                _ = await sampler.sample()
                try? await Task.sleep(for: .milliseconds(700))
            }
            while !Task.isCancelled {
                let snap = await sampler.sample()
                if Task.isCancelled { break }
                self.publish(snap)
                if open { await self.refreshExtras() }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}

/// Sabit kapasiteli kayan tampon: dolunca en eski deger duser.
struct RingBuffer<T> {
    let capacity: Int
    private var storage: [T] = []
    init(capacity: Int) { self.capacity = capacity }
    mutating func append(_ v: T) {
        if storage.count == capacity { storage.removeFirst() }
        storage.append(v)
    }
    var values: [T] { storage }
}
