// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için Türkçeye uyarlandı.
// Sağlayıcı JSON yanıtlarının ayrıştırılması (saf, ağsız).
import Foundation

public enum AIParse {
    /// Claude `/api/oauth/usage` ya da claude.ai usage JSON'u: "utilization" alanı olan her pencereyi alır.
    public static func claude(_ data: Data) -> [AILimit] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        let order = ["five_hour", "seven_day"]
        return root.compactMap { key, value -> AILimit? in
            // Hiç kullanılmamış hesapta ana pencereler null gelir: pencere henüz başlamamış, %0 demek
            let unused = order.contains(key) && (value is NSNull || (value as? [String: Any])?["utilization"] is NSNull)
            guard let util = unused ? 0 : ((value as? [String: Any])?["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let dict = value as? [String: Any] ?? [:]
            let date = (dict["resets_at"] as? String).flatMap { frac.date(from: $0) ?? plain.date(from: $0) }

            let label: String
            let window: TimeInterval?
            var model: String?
            var short: String?
            switch key {
            case "five_hour": label = "5 saat"; window = 18_000
            case "seven_day": label = "Haftalık"; window = 604_800
            default:
                // seven_day_opus, seven_day_sonnet ...: modele özel haftalık
                model = key.hasPrefix("seven_day_") ? String(key.dropFirst("seven_day_".count)) : key
                let names = ["opus": "Opus", "sonnet": "Sonnet", "oauth_apps": "Uygulamalar", "routines": "Rutinler",
                             "cowork": "Cowork", "extra_usage": "Ekstra"]
                if let name = names[model ?? key] {
                    label = key.hasPrefix("seven_day") ? "Haftalık · \(name)" : (key == "extra_usage" ? "Ekstra kullanım" : name)
                    short = name
                } else if dict["limit_dollars"] != nil {
                    // Anthropic'in kod adlı dolar kotası: dolar tutarı gösterilmez (iç birim, harcama değil)
                    label = "Ek kota"; short = "Ek kota"; model = AILimit.unnamed
                } else {
                    label = key.hasPrefix("seven_day") ? "Haftalık · diğer" : "Diğer limit"
                    short = "Diğer"; model = AILimit.unnamed
                }
                window = key.hasPrefix("seven_day") ? 604_800 : nil
            }
            return AILimit(id: "claude.\(key)", label: label, percent: util, resetsAt: date, window: window,
                           model: model, short: short, caption: key == "extra_usage" ? "kullanım" : nil)
        }
        .sorted { a, b in
            let ia = order.firstIndex { a.id == "claude.\($0)" } ?? Int.max
            let ib = order.firstIndex { b.id == "claude.\($0)" } ?? Int.max
            return ia != ib ? ia < ib : a.id < b.id
        }
    }

    /// Codex `wham/usage` yanıtı.
    public static func codex(_ root: [String: Any]) -> (plan: String?, limits: [AILimit]) {
        var limits: [AILimit] = []
        for (key, prefix) in [("rate_limit", ""), ("code_review_rate_limit", "Review, ")] {
            guard let group = root[key] as? [String: Any] else { continue }
            for slot in ["primary_window", "secondary_window"] {
                guard let w = group[slot] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                // Pencerenin anlamı konumdan değil süresinden okunur (5 sa / 7 gün yer değiştirebiliyor).
                let seconds = (w["limit_window_seconds"] as? NSNumber)?.doubleValue
                let reset = (w["reset_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                limits.append(AILimit(id: "codex.\(key).\(slot)", label: prefix + codexWindowName(seconds), percent: used,
                                      resetsAt: reset, window: seconds, model: prefix.isEmpty ? nil : "review",
                                      short: prefix.isEmpty ? nil : "Review"))
            }
        }
        limits.sort { ($0.window ?? .infinity) < ($1.window ?? .infinity) }
        return ((root["plan_type"] as? String)?.capitalized, limits)
    }

    private static func codexWindowName(_ seconds: Double?) -> String {
        guard let s = seconds else { return "Limit" }
        if s >= 604_800 { return "Haftalık" }
        if s >= 86_400 { return "\(Int(s / 86_400)) gün" }
        return "\(Int(s / 3600)) saat"
    }

    /// Cursor `usage-summary` yanıtı.
    public static func cursor(_ root: [String: Any]) -> (plan: String?, note: String?, limits: [AILimit]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: String) -> Date? {
            (root[key] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        }
        let start = date("billingCycleStart"), end = date("billingCycleEnd")
        let window = (start != nil && end != nil) ? end!.timeIntervalSince(start!) : 30 * 86_400

        let planUsage = (root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any]
        func num(_ key: String) -> Double? { (planUsage?[key] as? NSNumber)?.doubleValue }
        let used = num("used"), limit = num("limit")
        let total = num("totalPercentUsed") ?? (used != nil && (limit ?? 0) > 0 ? used! / limit! * 100 : nil)

        var limits: [AILimit] = []
        if let total {
            limits.append(AILimit(id: "cursor.plan", label: "Aylık dahil kullanım", percent: total, resetsAt: end, window: window, short: "Aylık"))
        }
        if let auto = num("autoPercentUsed") {
            limits.append(AILimit(id: "cursor.auto", label: "Auto ve Composer", percent: auto, resetsAt: end, window: window, model: "auto", short: "Auto"))
        }
        if let api = num("apiPercentUsed") {
            limits.append(AILimit(id: "cursor.api", label: "API modelleri", percent: api, resetsAt: end, window: window, model: "api", short: "API"))
        }
        let note: String? = {
            guard let used, let limit, limit > 0 else { return nil }
            let f = NumberFormatter()
            f.numberStyle = .currency; f.currencyCode = "USD"; f.locale = Locale(identifier: "tr_TR")
            f.maximumFractionDigits = 2
            return "\(f.string(from: NSNumber(value: used / 100)) ?? "") / \(f.string(from: NSNumber(value: limit / 100)) ?? "")"
        }()
        let plan = (root["membershipType"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized
        return (plan, note, limits)
    }

    /// JWT yük kısmı (claims).
    public static func jwtClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    public static func jwtExpiry(_ jwt: String) -> Date? {
        (jwtClaims(jwt)?["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
    }

    /// Cursor JWT'sinin "sub" alanındaki "...|user_xxx" -> "user_xxx" (süresi dolmuşsa nil).
    public static func cursorUserID(fromJWT jwt: String, now: Date = Date()) -> String? {
        guard let json = jwtClaims(jwt), let sub = json["sub"] as? String else { return nil }
        if let exp = (json["exp"] as? NSNumber)?.doubleValue, exp < now.timeIntervalSince1970 + 60 { return nil }
        return sub.split(separator: "|").last.map(String.init)
    }
}
