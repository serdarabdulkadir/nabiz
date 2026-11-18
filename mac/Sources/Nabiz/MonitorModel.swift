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
    let modelName = SystemInfo.modelName()
    let chipName = SystemInfo.chipName()

    var panelOpen = false {
        didSet { if oldValue != panelOpen { restart(); PhoneModel.shared.panelOpenChanged(panelOpen) } }
    }

    private let sampler = Sampler()

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
        AlertCenter.shared.macSnapshot(snap)
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
