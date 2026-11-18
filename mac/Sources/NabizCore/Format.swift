// Metin bicimleri. Ondalik ayraci Turkce virgul; nil -> "--".
import Foundation

public enum Format {
    public static let missing = "--"
    private static let tr = Locale(identifier: "tr_TR")

    private static func decimal(_ v: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", locale: tr, v)
    }

    /// 1536 -> "1,5 KB". base: 1024 (bellek) ya da 1000 (disk, Finder gibi).
    public static func bytes(_ value: UInt64?, base: Double = 1024) -> String {
        guard let value else { return missing }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = Double(value)
        var i = 0
        while v >= base && i < units.count - 1 { v /= base; i += 1 }
        if i == 0 { return "\(value) B" }
        return "\(decimal(v, digits: v < 100 ? 1 : 0)) \(units[i])"
    }

    public static func speed(_ bytesPerSecond: UInt64?) -> String {
        guard let bytesPerSecond else { return missing }
        return "\(bytes(bytesPerSecond))/s"
    }

    public static func percent(_ value: Int?) -> String {
        guard let value else { return missing }
        return "\(value)%"
    }

    public static func percent(fraction: Double?) -> String {
        guard let fraction else { return missing }
        return percent(Int((fraction * 100).rounded()))
    }

    /// 3725 sn -> "1 sa 2 dk"; 90000 -> "1 g 1 sa".
    public static func duration(seconds: Int?) -> String {
        guard let s = seconds, s >= 0 else { return missing }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d) g \(h) sa" }
        if h > 0 { return "\(h) sa \(m) dk" }
        return "\(m) dk"
    }

    public static func minutes(_ m: Int?) -> String {
        guard let m, m > 0 else { return missing }
        return duration(seconds: m * 60)
    }
}
