// Pil: IOPowerSources + AppleSmartBattery. Pil yoksa (masaustu Mac) nil.
import Foundation
import IOKit
import IOKit.ps

public enum BatterySampler {
    public static func read() -> BatteryStats? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let maxCap = (d[kIOPSMaxCapacityKey] as? Int) ?? 100
            let level = maxCap > 0 ? min(100, max(0, Int((Double(cur) / Double(maxCap) * 100).rounded()))) : cur
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            var minutes = d[key] as? Int
            if let m = minutes, m <= 0 { minutes = nil }
            let extra = smartBattery()
            return BatteryStats(level: level, charging: charging, health: extra.health, cycles: extra.cycles, minutes: minutes)
        }
        return nil
    }

    /// Saglik % = en yuksek gercek kapasite / tasarim kapasitesi.
    public static func healthPercent(maxCapacity: Int?, designCapacity: Int?) -> Int? {
        guard let m = maxCapacity, let d = designCapacity, d > 0, m > 0 else { return nil }
        return min(100, Int((Double(m) / Double(d) * 100).rounded()))
    }

    private static func smartBattery() -> (cycles: Int?, health: Int?) {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return (nil, nil) }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return (nil, nil) }
        let cycles = dict["CycleCount"] as? Int
        // 1) Sistemin kendi "Maksimum Kapasite" degeri (Sistem Ayarlari ile birebir). 2) Ham mAh orani:
        // yeni macOS'ta ham degerler "BatteryData" alt sozlugunde. Ust duzey MaxCapacity Apple Silicon'da hep
        // 100 (yuzde olcegi) oldugu icin saglik olarak KULLANILMAZ; okunamazsa nil ("--").
        let nested = dict["BatteryData"] as? [String: Any] ?? [:]
        let design = (dict["DesignCapacity"] as? Int) ?? (nested["DesignCapacity"] as? Int)
        let raw = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["NominalChargeCapacity"] as? Int)
            ?? (nested["NominalChargeCapacity"] as? Int)
        let health = SystemBatteryHealth.cached() ?? healthPercent(maxCapacity: raw, designCapacity: design)
        return (cycles, health)
    }
}

/// `system_profiler SPPowerDataType -json` icindeki sistem saglik yuzdesi; 6 saatte bir okunur (yavas komut).
enum SystemBatteryHealth {
    nonisolated(unsafe) private static var value: Int?
    nonisolated(unsafe) private static var readAt: Date?
    private static let lock = NSLock()

    static func cached() -> Int? {
        lock.lock(); defer { lock.unlock() }
        if let t = readAt, Date().timeIntervalSince(t) < 6 * 3600 { return value }
        readAt = Date()
        value = read()
        return value
    }

    private static func read() -> Int? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPPowerDataType", "-json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parse(data)
    }

    /// "sppower_battery_health_maximum_capacity": "%90" ya da "90%" -> 90.
    public static func parse(_ data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            if let info = item["sppower_battery_health_info"] as? [String: Any],
               let s = info["sppower_battery_health_maximum_capacity"] as? String,
               let n = Int(s.filter(\.isNumber)), (1...100).contains(n) { return n }
        }
        return nil
    }
}
