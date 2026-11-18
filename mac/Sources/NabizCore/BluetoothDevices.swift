// Bluetooth cihaz pilleri: IORegistry (Magic Keyboard/Mouse/Trackpad) + system_profiler JSON (AirPods, kulaklik).
import Foundation
import IOKit

public struct DeviceBattery: Sendable, Equatable {
    public var name: String
    /// 0...100
    public var percent: Int
    public init(name: String, percent: Int) { self.name = name; self.percent = percent }
}

public enum BluetoothParse {
    /// `system_profiler SPBluetoothDataType -json` ciktisindan bagli cihaz pilleri. Pil alani olmayan cihaz atlanir.
    public static func parseProfiler(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [DeviceBattery] = []
        for block in blocks {
            guard let connected = block["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let props = value as? [String: Any], let pct = percent(props) else { continue }
                    out.append(DeviceBattery(name: name, percent: pct))
                }
            }
        }
        return out
    }

    /// Ana pil, yoksa sol/sag kulakligin dusugu. Kilif pili cihaz pili sayilmaz.
    static func percent(_ props: [String: Any]) -> Int? {
        if let p = parsePercent(props["device_batteryLevelMain"]) { return p }
        let parts = [props["device_batteryLevelLeft"], props["device_batteryLevelRight"]].compactMap(parsePercent)
        return parts.min()
    }

    static func parsePercent(_ v: Any?) -> Int? {
        let s: String
        if let str = v as? String { s = str } else if let n = v as? NSNumber { s = n.stringValue } else { return nil }
        guard let n = Int(s.filter(\.isNumber)), (0...100).contains(n) else { return nil }
        return n
    }

    /// Ayni ada sahip ilk kayit kalir (IORegistry once gelir); ada gore sirali.
    public static func merge(_ lists: [[DeviceBattery]]) -> [DeviceBattery] {
        var seen = Set<String>()
        var out: [DeviceBattery] = []
        for d in lists.joined() where !d.name.isEmpty && seen.insert(d.name).inserted { out.append(d) }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public actor DeviceSampler {
    private var cache: [DeviceBattery] = []
    private var lastRead: Date?
    private var inFlight = false

    public init() {}

    /// En cok 60 sn'de bir gercekten okur; aradaki cagrilar onbellegi doner. Ana is parcacigi disinda.
    public func read(minInterval: TimeInterval = 60) async -> [DeviceBattery] {
        if let t = lastRead, Date().timeIntervalSince(t) < minInterval { return cache }
        guard !inFlight else { return cache }
        inFlight = true
        defer { inFlight = false }
        let hid = Self.readHID()
        let profiler = await Self.runProfiler(timeout: 8)
        cache = BluetoothParse.merge([hid, profiler])
        lastRead = Date()
        return cache
    }

    private static func readHID() -> [DeviceBattery] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }
        var out: [DeviceBattery] = []
        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let name = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? String,
                  let pct = (IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue,
                  (0...100).contains(pct) else { continue }
            out.append(DeviceBattery(name: name, percent: pct))
        }
        return out
    }

    private static func runProfiler(timeout: TimeInterval) async -> [DeviceBattery] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                p.arguments = ["SPBluetoothDataType", "-json"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: []); return }
                let pid = p.processIdentifier
                // Zaman asimi: sure dolunca sureci sonlandir; okuma EOF ile biter.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { kill(pid, SIGKILL) } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: p.terminationStatus == 0 ? BluetoothParse.parseProfiler(data) : [])
            }
        }
    }
}
