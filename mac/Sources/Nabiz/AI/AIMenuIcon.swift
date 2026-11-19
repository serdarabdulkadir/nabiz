// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız menü çubuğu öğesinin sonuna çizilir.
import AppKit
import NabizCore

/// AI simgesi / sütunu seçimi (Ayarlar > Menü Çubuğu; UserDefaults "ai.barStyle").
enum AIBarStyle: String, CaseIterable, Identifiable {
    case column, recentTwo, mostFull, sideBySide, bars
    var id: String { rawValue }

    var title: String {
        switch self {
        case .column: "Yalnız yüzde (sütun)"
        case .recentTwo: "Son kullanılan iki"
        case .mostFull: "En dolu"
        case .sideBySide: "Yan yana"
        case .bars: "Barlar"
        }
    }

    var detail: String {
        switch self {
        case .column: "Diğer sütunlar gibi: AI ve seçilen hesabın 5 saatlik yüzdesi."
        case .recentTwo: "En son kullandığın iki sağlayıcı, iç içe halkalar."
        case .mostFull: "Limite en yakın sağlayıcı, ortasında logosu."
        case .sideBySide: "Her sağlayıcı kendi halkası ve logosuyla."
        case .bars: "Her sağlayıcı için ince bir bar."
        }
    }
}

/// Menü çubuğu simgesi, uygulama ikonundaki 270° halkalar. Çizim rengi (`label`) çağıran tarafından verilir
/// (şablon / açık / koyu menü çubuğuna uysun).
enum AIMenuIcon {
    struct Entry: Equatable {
        let provider: AIProviderID
        let percent: Double?
        let resetsAt: Date?
        var lastUsed: TimeInterval = 0
        var logo: BrandLogo { provider.logo }
        var key: String { "\(provider.rawValue):\(Int((percent ?? -1).rounded())):\(Int(lastUsed / 60))" }
    }

    static let claudeOrange = NSColor(red: 0.93, green: 0.52, blue: 0.36, alpha: 1)
    static let cursorBlue = NSColor(red: 0.42, green: 0.55, blue: 0.98, alpha: 1)
    static let critical = NSColor(red: 0.94, green: 0.33, blue: 0.29, alpha: 1)

    private static func tint(_ e: Entry, label: NSColor) -> NSColor {
        switch e.provider {
        case .claude: claudeOrange
        case .codex: label
        case .cursor: cursorBlue
        }
    }

    static func image(_ entries: [Entry], style: AIBarStyle, label: NSColor) -> NSImage {
        switch style {
        case _ where entries.count <= 1:
            return stacked(outer: entries.first, inner: nil, label: label)
        case .recentTwo, .column:
            // En son kullanılan önce; dış halka o
            let sorted = entries.enumerated().sorted { a, b in
                a.element.lastUsed != b.element.lastUsed ? a.element.lastUsed > b.element.lastUsed : a.offset < b.offset
            }.map(\.element)
            // Hiç kullanılmamış ve boş sağlayıcı iç halkayı boş yere doldurmasın
            let inner = sorted.dropFirst().first.flatMap { $0.lastUsed > 0 || ($0.percent ?? 0) > 0 ? $0 : nil }
            return stacked(outer: sorted.first, inner: inner, label: label)
        case .mostFull:
            return focused(entries.max { ($0.percent ?? -1) < ($1.percent ?? -1) }!, label: label)
        case .sideBySide:
            return sideBySide(entries, label: label)
        case .bars:
            return bars(entries, label: label)
        }
    }

    private static func sideBySide(_ entries: [Entry], label: NSColor) -> NSImage {
        let step: CGFloat = 23
        let image = NSImage(size: NSSize(width: step * CGFloat(entries.count) - 1, height: 22), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            for (i, e) in entries.enumerated() {
                let c = CGPoint(x: 11 + CGFloat(i) * step, y: 10.7)
                ring(ctx, center: c, radius: 9, value: e.percent, track: label.withAlphaComponent(0.22),
                     fill: (e.percent ?? 0) >= 90 ? critical : tint(e, label: label), width: 2.4)
                var t = CGAffineTransform(translationX: c.x - 4.6, y: c.y + 4.6).scaledBy(x: 9.2 / 24, y: -9.2 / 24)
                if let p = e.logo.cgPath.copy(using: &t) { ctx.addPath(p); ctx.setFillColor(label.cgColor); ctx.fillPath() }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func bars(_ entries: [Entry], label: NSColor) -> NSImage {
        let shown = Array(entries.prefix(3))
        let image = NSImage(size: NSSize(width: 38, height: 22), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let gap: CGFloat = shown.count == 3 ? 7 : 8.5
            let top: CGFloat = shown.count == 3 ? 16.5 : 14
            for (i, e) in shown.enumerated() {
                let rect = CGRect(x: 2, y: top - CGFloat(i) * gap, width: 34, height: 4)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil))
                ctx.setFillColor(label.withAlphaComponent(0.22).cgColor); ctx.fillPath()
                let f = CGFloat(min(max((e.percent ?? 0) / 100, 0), 1))
                if f > 0 {
                    ctx.addPath(CGPath(roundedRect: CGRect(x: 2, y: rect.minY, width: max(34 * f, 4), height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil))
                    ctx.setFillColor(((e.percent ?? 0) >= 90 ? critical : tint(e, label: label)).cgColor); ctx.fillPath()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// İç içe halkalar; her halka kendi sağlayıcısının renginde (%90+ kırmızı)
    private static func stacked(outer: Entry?, inner: Entry?, label: NSColor) -> NSImage {
        let hasInner = inner != nil
        func fill(_ e: Entry?) -> NSColor { (e?.percent ?? 0) >= 90 ? critical : (e.map { tint($0, label: label) } ?? label) }
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY - 0.3)
            ring(ctx, center: center, radius: hasInner ? 9.2 : 8.6, value: outer?.percent, track: label.withAlphaComponent(0.22), fill: fill(outer))
            if hasInner { ring(ctx, center: center, radius: 4.8, value: inner?.percent, track: label.withAlphaComponent(0.22), fill: fill(inner), width: 2.6) }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func focused(_ entry: Entry, label: NSColor) -> NSImage {
        let percent = entry.percent ?? 0
        let text = (percent >= 90 && entry.resetsAt != nil) ? clock(entry.resetsAt!) as NSString : nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        let textWidth = text.map { ceil($0.size(withAttributes: [.font: font]).width) + 3 } ?? 0
        let image = NSImage(size: NSSize(width: 22 + textWidth, height: 22), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: 11, y: 10.7)
            ring(ctx, center: center, radius: 9.2, value: entry.percent, track: label.withAlphaComponent(0.22),
                 fill: percent >= 90 ? critical : claudeOrange)
            var t = CGAffineTransform(translationX: 6.6, y: 15.1).scaledBy(x: 8.8 / 24, y: -8.8 / 24)
            if let path = entry.logo.cgPath.copy(using: &t) { ctx.addPath(path); ctx.setFillColor(label.cgColor); ctx.fillPath() }
            if let text {
                text.draw(at: NSPoint(x: 25, y: (22 - font.ascender + font.descender) / 2 - 0.5),
                          withAttributes: [.font: font, .foregroundColor: label])
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// "1:20" (saat:dakika) ya da "2g"
    private static func clock(_ date: Date) -> String {
        let s = max(Int(date.timeIntervalSinceNow), 0)
        if s >= 86_400 { return "\(s / 86_400)g" }
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// Altta açıklığı olan, sol alttan saat yönünde dolan halka
    private static func ring(_ ctx: CGContext, center: CGPoint, radius: CGFloat, value: Double?, track: NSColor, fill: NSColor, width: CGFloat = 2.6) {
        let start = CGFloat.pi * 1.25, sweep = CGFloat.pi * 1.5
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
        ctx.setStrokeColor(track.cgColor)
        ctx.strokePath()
        guard let value else { return }
        let fraction = CGFloat(min(max(value / 100, 0), 1))
        guard fraction > 0 else { return }
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep * fraction, clockwise: true)
        ctx.setStrokeColor(fill.cgColor)
        ctx.strokePath()
    }
}
