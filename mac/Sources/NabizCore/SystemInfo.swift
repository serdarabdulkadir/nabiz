// Calisma suresi, model adi, cip adi ve sysctl yardimcilari.
import Foundation
import IOKit

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    // 32 bit sonuclar da Int64 tamponuna sigar; boyut kontrolu icin once boyutu sor.
    var probe = 0
    guard sysctlbyname(name, nil, &probe, nil, 0) == 0 else { return nil }
    if probe == MemoryLayout<Int32>.size {
        var v: Int32 = 0
        var s = probe
        guard sysctlbyname(name, &v, &s, nil, 0) == 0 else { return nil }
        return Int(v)
    }
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

public enum SystemInfo {
    /// Acilistan beri gecen saniye (uykuda gecen sure dahil).
    public static func uptimeSeconds() -> Int? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else { return nil }
        return max(0, Int(Date().timeIntervalSince1970) - Int(tv.tv_sec))
    }

    /// Ornek: "MacBook Pro" ya da yoksa hw.model ("Mac15,3").
    public static func modelName() -> String? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        if svc != 0 {
            defer { IOObjectRelease(svc) }
            if let data = IORegistryEntryCreateCFProperty(svc, "product-name" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data {
                let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
                if !s.isEmpty { return s }
            }
        }
        return sysctlString("hw.model")
    }

    /// Ornek: "Apple M3 Pro".
    public static func chipName() -> String? {
        sysctlString("machdep.cpu.brand_string")
    }
}
