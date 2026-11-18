// Tum olcumleri toplar; CPU ve ag icin iki ornek arasi farki tutar. Ana is parcacigi disinda calisir.
import Foundation

public actor Sampler {
    private var lastTicks: [CoreTicks]?
    private var lastNet: (rx: UInt64, tx: UInt64)?
    private var lastTime: Date?
    private let counts = CPUSampler.coreCounts()

    public init() {}

    public func sample() -> Snapshot {
        let now = Date()
        var snap = Snapshot(ts: Int(now.timeIntervalSince1970))

        if let ticks = CPUSampler.readTicks() {
            if let prev = lastTicks, let u = CPUSampler.usage(previous: prev, current: ticks) {
                snap.cpu = CPUStats(total: Int(u.total.rounded()), cores: u.cores.map { Int($0.rounded()) },
                                    perfCores: counts.perf, effCores: counts.eff)
            }
            lastTicks = ticks
        }

        if let totals = NetworkSampler.readTotals() {
            if let prev = lastNet, let t = lastTime {
                let dt = now.timeIntervalSince(t)
                snap.net = NetStats(up: NetworkSampler.rate(previous: prev.tx, current: totals.tx, seconds: dt),
                                    down: NetworkSampler.rate(previous: prev.rx, current: totals.rx, seconds: dt))
            }
            lastNet = totals
        }
        lastTime = now

        snap.mem = MemorySampler.read()
        snap.disk = DiskSampler.read()
        snap.battery = BatterySampler.read()
        snap.gpu = GPUSampler.read()
        snap.uptime = SystemInfo.uptimeSeconds()
        return snap
    }
}
