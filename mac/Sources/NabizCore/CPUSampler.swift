// CPU kullanimi: host_processor_info sayac farki (iki ornek arasi).
import Foundation
import Darwin

public struct CoreTicks: Sendable, Equatable {
    public var user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public struct CPUUsage: Sendable, Equatable {
    /// 0...100
    public var total: Double
    public var cores: [Double]
}

public enum CPUSampler {
    /// Iki tick dizisi arasindaki kullanim. Sayaclar 32 bit oldugundan fark tasmaya dayanikli hesaplanir.
    public static func usage(previous: [CoreTicks], current: [CoreTicks]) -> CPUUsage? {
        guard !current.isEmpty, previous.count == current.count else { return nil }
        var cores: [Double] = []
        var busySum: UInt64 = 0
        var totalSum: UInt64 = 0
        for (p, c) in zip(previous, current) {
            let u = UInt64(c.user &- p.user), s = UInt64(c.system &- p.system)
            let n = UInt64(c.nice &- p.nice), i = UInt64(c.idle &- p.idle)
            let busy = u + s + n
            let total = busy + i
            cores.append(total == 0 ? 0 : Double(busy) / Double(total) * 100)
            busySum += busy
            totalSum += total
        }
        return CPUUsage(total: totalSum == 0 ? 0 : Double(busySum) / Double(totalSum) * 100, cores: cores)
    }

    public static func readTicks() -> [CoreTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard r == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { i in
            let b = i * stride
            return CoreTicks(
                user: UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)]))
        }
    }

    /// Performans / verimlilik cekirdek sayisi (Apple Silicon); okunamazsa nil.
    public static func coreCounts() -> (perf: Int?, eff: Int?) {
        (sysctlInt("hw.perflevel0.logicalcpu"), sysctlInt("hw.perflevel1.logicalcpu"))
    }
}
