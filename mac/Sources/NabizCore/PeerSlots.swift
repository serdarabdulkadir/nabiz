import Foundation

/// Tek oturum kurali (docs/protokol.md bolum 11): en cok 1 aktif + 1 aday baglanti.
/// Yeni baglanti eski oturumu hemen dusurmez; aday dogrulaninca (kuruldu) aktif olur, eskisi kapanir.
public struct ConnectionSlots: Equatable, Sendable {
    /// Adayin el sikisma suresi (sn); dolunca kapatilir.
    public static let candidateTimeout: TimeInterval = 10

    public enum Decision: Equatable, Sendable { case aday, reddet }

    public private(set) var active: Int?
    public private(set) var candidate: Int?

    public init() {}

    /// Yeni gelen baglanti: aday yeri bossa aday, degilse reddedilir (hemen kapatilmali).
    public mutating func opened(_ id: Int) -> Decision {
        guard candidate == nil else { return .reddet }
        candidate = id
        return .aday
    }

    /// Aday dogrulandi. Donus: aktif olduysa `promoted`, ve dusurulmesi gereken eski aktif baglanti.
    public mutating func promote(_ id: Int) -> (promoted: Bool, replaced: Int?) {
        guard candidate == id else { return (false, nil) }
        let old = active
        active = id; candidate = nil
        return (true, old)
    }

    /// Baglanti kapandi. Donus: aktif miydi.
    @discardableResult
    public mutating func closed(_ id: Int) -> Bool {
        if candidate == id { candidate = nil }
        if active == id { active = nil; return true }
        return false
    }
}
