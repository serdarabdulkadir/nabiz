// Sabit kapasiteli halka tampon: dolunca en eski deger duser. Gecmis grafikleri icin.
import Foundation

public struct History<Element: Sendable>: Sendable {
    public let capacity: Int
    private var storage: [Element?]
    private var head = 0
    public private(set) var count = 0

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
        storage = Array(repeating: nil, count: max(1, capacity))
    }

    public var isEmpty: Bool { count == 0 }

    public mutating func append(_ v: Element) {
        if count < capacity {
            storage[(head + count) % capacity] = v
            count += 1
        } else {
            storage[head] = v
            head = (head + 1) % capacity
        }
    }

    /// Eskiden yeniye sirali degerler.
    public var values: [Element] {
        (0..<count).compactMap { storage[(head + $0) % capacity] }
    }

    public var last: Element? { count == 0 ? nil : storage[(head + count - 1) % capacity] }

    /// Bastan itibaren kosulu saglayan en eski ogeleri atar (zaman damgasi suzmesi icin).
    public mutating func removeOldest(while shouldRemove: (Element) -> Bool) {
        while count > 0, let first = storage[head], shouldRemove(first) {
            storage[head] = nil
            head = (head + 1) % capacity
            count -= 1
        }
    }
}

/// Mac'e ozel gecmis noktasi (protokol Snapshot'inin disinda). ts: 1970'ten beri saniye.
public struct HistoryPoint: Sendable, Equatable {
    public var ts: Double
    public var cpu: Int?
    /// 0...1
    public var mem: Double?
    public var down: UInt64?
    public var up: UInt64?
    public init(ts: Double, cpu: Int? = nil, mem: Double? = nil, down: UInt64? = nil, up: UInt64? = nil) {
        self.ts = ts; self.cpu = cpu; self.mem = mem; self.down = down; self.up = up
    }

    public init(snapshot s: Snapshot) {
        self.init(ts: Double(s.ts), cpu: s.cpu?.total,
                  mem: s.mem.flatMap { $0.total > 0 ? Double($0.used) / Double($0.total) : nil },
                  down: s.net?.down, up: s.net?.up)
    }
}
