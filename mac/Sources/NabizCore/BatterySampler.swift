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
        let design = dict["DesignCapacity"] as? Int
        // Apple Silicon'da MaxCapacity yuzdedir; ham mAh degeri AppleRawMaxCapacity'dedir.
        let raw = (dict["AppleRawMaxCapacity"] as? Int) ?? (dict["NominalChargeCapacity"] as? Int)
        var health = healthPercent(maxCapacity: raw, designCapacity: design)
        if health == nil, let m = dict["MaxCapacity"] as? Int, m <= 100, m > 0 { health = m }
        return (cycles, health)
    }
}
