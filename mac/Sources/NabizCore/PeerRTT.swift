import Foundation

/// Gecikme olcumu (docs/protokol.md bolum 7, Gecikme). Saf mantik: saat disaridan (monoton saniye) verilir.
/// `ping` id ile gonderilir, ayni id'li `pong` gelince RTT (ms) olculur; son 5 olcumun ortancasi gosterilir.
public struct RTTTracker: Sendable {
    public static let windowSize = 5
    private static let maxPending = 8

    private var nextId = 1
    private var pending: [(id: Int, sentAt: Double)] = []
    private var samples: [Int] = []

    public init() {}

    /// Yeni ping icin id ayirir ve gonderim anini kaydeder.
    public mutating func pingSent(at now: Double) -> Int {
        let id = nextId; nextId += 1
        pending.append((id, now))
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
        return id
    }

    /// Pong geldi. Bilinen id ise RTT (ms) kaydedilir ve dondurulur; `id`siz/bilinmeyen pong yok sayilir (nil).
    @discardableResult
    public mutating func pongReceived(id: Int?, at now: Double) -> Int? {
        guard let id, let i = pending.firstIndex(where: { $0.id == id }) else { return nil }
        let rtt = max(0, Int(((now - pending[i].sentAt) * 1000).rounded()))
        pending.remove(at: i)
        samples.append(rtt)
        if samples.count > Self.windowSize { samples.removeFirst(samples.count - Self.windowSize) }
        return rtt
    }

    /// Son (en cok 5) olcumun ortancasi (ms); olcum yoksa nil.
    public var medianMs: Int? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2] + 1) / 2
    }

    /// Yeni oturum: bekleyenler ve olcumler silinir (id sayaci artmaya devam eder).
    public mutating func reset() { pending = []; samples = [] }
}
