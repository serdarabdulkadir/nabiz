// Disk: / hacmi.
import Foundation

public enum DiskSampler {
    public static func read() -> DiskStats? {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, total > 0,
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        let t = UInt64(total)
        let f = min(UInt64(max(0, free)), t)
        return DiskStats(used: t - f, total: t)
    }
}
