// Olcum modeli. Alanlar docs/protokol.md `stats` ile ayni adlardadir; gpu ve uptime Mac'e ozel eklerdir.
import Foundation

public struct CPUStats: Codable, Sendable, Equatable {
    public var total: Int
    public var cores: [Int]
    public var perfCores: Int?
    public var effCores: Int?
    public init(total: Int, cores: [Int], perfCores: Int? = nil, effCores: Int? = nil) {
        self.total = total; self.cores = cores; self.perfCores = perfCores; self.effCores = effCores
    }
}

public struct MemStats: Codable, Sendable, Equatable {
    public var used: UInt64
    public var total: UInt64
    /// "normal", "warn" ya da "critical"; okunamazsa nil.
    public var pressure: String?
    public init(used: UInt64, total: UInt64, pressure: String? = nil) {
        self.used = used; self.total = total; self.pressure = pressure
    }
}

public struct DiskStats: Codable, Sendable, Equatable {
    public var used: UInt64
    public var total: UInt64
    public init(used: UInt64, total: UInt64) { self.used = used; self.total = total }
}

public struct BatteryStats: Codable, Sendable, Equatable {
    public var level: Int
    public var charging: Bool
    public var health: Int?
    public var cycles: Int?
    /// Dakika: sarjdaysa dolmaya, degilse bitmeye kalan.
    public var minutes: Int?
    /// Santigrat; yalniz Android yazar (Mac yazmaz).
    public var temp: Double?
    public init(level: Int, charging: Bool, health: Int? = nil, cycles: Int? = nil, minutes: Int? = nil, temp: Double? = nil) {
        self.level = level; self.charging = charging; self.health = health; self.cycles = cycles
        self.minutes = minutes; self.temp = temp
    }
}

public struct NetStats: Codable, Sendable, Equatable {
    public var up: UInt64
    public var down: UInt64
    public init(up: UInt64, down: UInt64) { self.up = up; self.down = down }
}

public struct Snapshot: Codable, Sendable, Equatable {
    public var ts: Int
    public var cpu: CPUStats?
    public var mem: MemStats?
    public var disk: DiskStats?
    public var battery: BatteryStats?
    public var net: NetStats?
    public var gpu: Int?
    public var uptime: Int?
    /// "normal" | "warn" | "critical"; yalniz Android yazar.
    public var thermal: String?
    public init(ts: Int, cpu: CPUStats? = nil, mem: MemStats? = nil, disk: DiskStats? = nil,
                battery: BatteryStats? = nil, net: NetStats? = nil, gpu: Int? = nil, uptime: Int? = nil, thermal: String? = nil) {
        self.ts = ts; self.cpu = cpu; self.mem = mem; self.disk = disk
        self.battery = battery; self.net = net; self.gpu = gpu; self.uptime = uptime; self.thermal = thermal
    }
}
