// Bellek: host_statistics64 + basinc seviyesi.
import Foundation
import Darwin

public enum MemorySampler {
    /// Kullanilan = uygulama (internal - purgeable) + wired + sikistirilmis.
    public static func usedBytes(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                                 compressedPages: UInt64, pageSize: UInt64) -> UInt64 {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (app + wiredPages + compressedPages) * pageSize
    }

    public static func read() -> MemStats? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let used = usedBytes(internalPages: UInt64(stats.internal_page_count),
                             purgeablePages: UInt64(stats.purgeable_count),
                             wiredPages: UInt64(stats.wire_count),
                             compressedPages: UInt64(stats.compressor_page_count),
                             pageSize: UInt64(getpagesize()))
        return MemStats(used: used, total: ProcessInfo.processInfo.physicalMemory, pressure: pressure())
    }

    public static func pressure() -> String? {
        pressureName(level: sysctlInt("kern.memorystatus_vm_pressure_level"))
    }

    public static func pressureName(level: Int?) -> String? {
        switch level {
        case 1: return "normal"
        case 2: return "warn"
        case 4: return "critical"
        default: return nil
        }
    }
}
