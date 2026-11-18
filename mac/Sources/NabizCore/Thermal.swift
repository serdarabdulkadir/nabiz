// Sicaklik (IOHIDEventSystemClient, private semboller dlsym ile) ve fan (AppleSMC). Basarisizlik nil doner, cokmez.
import Foundation
import IOKit
import Darwin

public enum ThermalMath {
    /// CPU die sensorleri: Apple Silicon'da "PMU tdie*" ve "pACC/eACC MTR Temp". Gecerli (1...150 C) olanlarin en yuksegi.
    public static func cpuTemperature(_ readings: [(name: String, value: Double)]) -> Double? {
        let cpu = readings.filter { r in
            (r.name.contains("tdie") || r.name.contains("ACC MTR Temp")) && r.value > 1 && r.value < 150
        }
        return cpu.map(\.value).max()
    }
}

public enum SMCDecode {
    /// SMC veri tipine gore sayi cozumu (bayt sirasi: flt Apple Silicon'da little-endian, digerleri big-endian).
    public static func value(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : nil
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }
}

public enum ThermalSampler {
    /// CPU sicakligi (C); okunamazsa nil.
    public static func cpuTemperature() -> Double? {
        ThermalMath.cpuTemperature(HIDSensors.readAll())
    }

    /// Fan hizlari (rpm). Fansiz Mac'te (FNum = 0 ya da anahtar yok) bos dizi.
    public static func fanSpeeds() -> [Int] {
        guard let smc = SMC() else { return [] }
        defer { smc.close() }
        guard let n = smc.read("FNum"), n >= 1 else { return [] }
        var out: [Int] = []
        for i in 0..<min(Int(n), 4) {
            if let rpm = smc.read("F\(i)Ac"), rpm >= 0, rpm < 20000 { out.append(Int(rpm.rounded())) }
        }
        return out
    }
}

// MARK: IOHIDEventSystemClient

private enum HIDSensors {
    typealias CreateFn = @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias SetMatchingFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Int32
    typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> UnsafeMutableRawPointer?
    typealias CopyEventFn = @convention(c) (UnsafeMutableRawPointer?, Int64, Int32, Int64) -> UnsafeMutableRawPointer?
    typealias FloatValueFn = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Double

    static let temperatureEvent: Int64 = 15

    static func readAll() -> [(name: String, value: Double)] {
        guard let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let s1 = dlsym(lib, "IOHIDEventSystemClientCreate"),
              let s2 = dlsym(lib, "IOHIDEventSystemClientSetMatching"),
              let s3 = dlsym(lib, "IOHIDEventSystemClientCopyServices"),
              let s4 = dlsym(lib, "IOHIDServiceClientCopyProperty"),
              let s5 = dlsym(lib, "IOHIDServiceClientCopyEvent"),
              let s6 = dlsym(lib, "IOHIDEventGetFloatValue")
        else { return [] }
        let create = unsafeBitCast(s1, to: CreateFn.self)
        let setMatching = unsafeBitCast(s2, to: SetMatchingFn.self)
        let copyServices = unsafeBitCast(s3, to: CopyServicesFn.self)
        let copyProperty = unsafeBitCast(s4, to: CopyPropertyFn.self)
        let copyEvent = unsafeBitCast(s5, to: CopyEventFn.self)
        let floatValue = unsafeBitCast(s6, to: FloatValueFn.self)

        guard let client = create(nil) else { return [] }
        defer { Unmanaged<AnyObject>.fromOpaque(client).release() }

        let match: NSDictionary = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = setMatching(client, UnsafeRawPointer(Unmanaged.passUnretained(match).toOpaque()))
        guard let servicesPtr = copyServices(client) else { return [] }
        let services = Unmanaged<CFArray>.fromOpaque(servicesPtr).takeRetainedValue()

        var out: [(name: String, value: Double)] = []
        let productKey = "Product" as NSString
        for i in 0..<CFArrayGetCount(services) {
            guard let svc = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = UnsafeMutableRawPointer(mutating: svc)
            guard let namePtr = copyProperty(service, UnsafeRawPointer(Unmanaged.passUnretained(productKey).toOpaque())),
                  let name = Unmanaged<AnyObject>.fromOpaque(namePtr).takeRetainedValue() as? String
            else { continue }
            guard let event = copyEvent(service, temperatureEvent, 0, 0) else { continue }
            defer { Unmanaged<AnyObject>.fromOpaque(event).release() }
            let v = floatValue(event, Int32(truncatingIfNeeded: temperatureEvent << 16))
            if v.isFinite { out.append((name, v)) }
        }
        return out
    }
}

// MARK: AppleSMC

private final class SMC {
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
    private struct Param {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private var conn: io_connect_t = 0

    init?() {
        guard MemoryLayout<Param>.size == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess, conn != 0 else { return nil }
    }

    func close() { if conn != 0 { IOServiceClose(conn); conn = 0 } }

    private func call(_ input: inout Param) -> Param? {
        var output = Param()
        var outSize = MemoryLayout<Param>.size
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<Param>.size, &output, &outSize)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    func read(_ key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }
        let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        var info = Param()
        info.key = code
        info.data8 = 9
        guard let infoOut = call(&info) else { return nil }
        let size = Int(infoOut.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }
        var req = Param()
        req.key = code
        req.keyInfo.dataSize = infoOut.keyInfo.dataSize
        req.data8 = 5
        guard let out = call(&req) else { return nil }
        let typeCode = infoOut.keyInfo.dataType
        let type = String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: typeCode >> UInt32($0)) }, as: UTF8.self)
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(size)) }
        return SMCDecode.value(type: type, bytes: bytes)
    }
}
