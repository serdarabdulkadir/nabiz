// En cok CPU kullanan surecler: proc_pidinfo(PROC_PIDTASKINFO) toplam CPU zamani farki.
// Olcek Activity Monitor gibi: tek cekirdek = %100 (cekirdek sayisina bolunmez).
import Foundation
import Darwin

public struct ProcessUsage: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    /// Tek cekirdek = 100
    public var percent: Double
    public init(pid: Int32, name: String, percent: Double) {
        self.pid = pid; self.name = name; self.percent = percent
    }
}

public enum ProcessMath {
    /// Iki toplam CPU-zamani ornegi (ns) arasi yuzde, en yuksek `limit` surec. Yeni (onceki ornegi olmayan)
    /// ya da sayaci geri giden surecler atlanir; sifir kullanim listelenmez.
    public static func top(previous: [Int32: UInt64], current: [Int32: UInt64],
                           elapsedNanos: Double, limit: Int) -> [(pid: Int32, percent: Double)] {
        guard elapsedNanos > 0, limit > 0 else { return [] }
        var out: [(pid: Int32, percent: Double)] = []
        for (pid, now) in current {
            guard let before = previous[pid], now > before else { continue }
            let p = Double(now - before) / elapsedNanos * 100
            if p > 0.05 { out.append((pid, p)) }
        }
        out.sort { $0.percent != $1.percent ? $0.percent > $1.percent : $0.pid < $1.pid }
        return Array(out.prefix(limit))
    }
}

public actor ProcessSampler {
    private var previous: [Int32: UInt64] = [:]
    private var lastTime: Date?
    private let timebase: (numer: UInt64, denom: UInt64)

    public init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebase = (UInt64(tb.numer), UInt64(max(tb.denom, 1)))
    }

    /// Ilk cagrida (ya da uzun aradan sonra) bos doner; kullanim iki ornek arasi olculur.
    public func sample(limit: Int = 5) -> [ProcessUsage] {
        let now = Date()
        let current = readTotals()
        defer { previous = current; lastTime = now }
        guard let t = lastTime, now.timeIntervalSince(t) < 30 else { return [] }
        let top = ProcessMath.top(previous: previous, current: current,
                                  elapsedNanos: now.timeIntervalSince(t) * 1e9, limit: limit)
        return top.map { ProcessUsage(pid: $0.pid, name: Self.name(of: $0.pid), percent: $0.percent) }
    }

    /// pid -> toplam (user + system) CPU zamani, nanosaniye.
    private func readTotals() -> [Int32: UInt64] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [:] }
        var pids = [Int32](repeating: 0, count: Int(n) + 64)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [:] }
        let count = min(pids.count, Int(bytes) / MemoryLayout<Int32>.size)
        var out: [Int32: UInt64] = [:]
        out.reserveCapacity(count)
        for pid in pids[0..<count] where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            out[pid] = ticks &* timebase.numer / timebase.denom
        }
        return out
    }

    private static func name(of pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return "pid \(pid)" }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
