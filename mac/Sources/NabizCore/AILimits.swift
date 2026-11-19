// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi.
// AI limitlerinin saf modeli ve mantığı: limit, sağlayıcı durumu, ipucu, ön limitler, yenileme takvimi, eşik bildirimi, tel biçimi.
import Foundation

public enum AIProviderID: String, CaseIterable, Sendable, Identifiable, Codable {
    case claude, codex, cursor
    public var id: String { rawValue }
    public var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

public struct AILimit: Equatable, Sendable, Identifiable {
    /// Anthropic'in kod adlı (ne ölçtüğü belgelenmemiş) sayaçları: ön yüze yalnızca %90+ çıkar.
    public static let unnamed = "unnamed"

    public var id: String
    public let label: String
    public let used: Double            // okunan yüzde (0-100)
    public let resetsAt: Date?
    public let window: TimeInterval?   // pencere uzunluğu (sn)
    public var model: String?          // modele özel limit (opus, sonnet, review); nil = genel
    public var short: String?          // halka altındaki kısa ad
    public var caption: String?

    public init(id: String, label: String, percent: Double, resetsAt: Date?, window: TimeInterval?,
                model: String? = nil, short: String? = nil, caption: String? = nil) {
        self.id = id; self.label = label; used = percent; self.resetsAt = resetsAt; self.window = window
        self.model = model; self.short = short; self.caption = caption
    }

    /// Sıfırlanma anı geçtiyse pencere yenilenmiştir: yeni veri gelene kadar eski yüzde gösterilmez.
    public func didReset(at now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }
    public func percent(at now: Date = Date()) -> Double { didReset(at: now) ? 0 : used }

    /// 0 sakin, 1 yüksek ya da tempodan hızlı (geçen sürenin %10 fazlası), 2 kritik (%90+).
    public func level(at now: Date = Date()) -> Int {
        let p = percent(at: now)
        if p >= 90 { return 2 }
        var overPace = false
        if let window, window > 0, let resetsAt {
            let elapsed = min(max(1 - resetsAt.timeIntervalSince(now) / window, 0), 1)
            overPace = p / 100 > elapsed + 0.1
        }
        return (p >= 75 || overPace) ? 1 : 0
    }

    /// Pencere başından beri ortalama hızla devam edilirse dolmasına kalan süre. Yalnız belirgin biçimde erken
    /// dolacaksa (kalan sürenin %90'ından önce) döner; veri yetersizse (pencerenin ilk %5'i) nil.
    public func timeToFull(at now: Date = Date()) -> TimeInterval? {
        let p = percent(at: now)
        guard let window, let resetsAt, p > 0, p < 100 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        let elapsed = window - remaining
        guard remaining > 0, elapsed > window * 0.05 else { return nil }
        let eta = (100 - p) / (p / elapsed)
        return eta < remaining * 0.9 ? eta : nil
    }
}

public enum AIProviderState: Equatable, Sendable { case loading, ok, needsLogin, error(String) }

/// Sağlayıcı getiricilerinin ortak hataları.
public enum AIFetchError: Error, Equatable, Sendable {
    case notInstalled, needsPermission, expired, needsLogin, badResponse
    case http(Int)
    case offline
}

/// Veri alınamadığında kartın altında görünen ipucu: neden + tek düzeltme.
public struct AIIssue: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case login, retry, allowKeychain, openApp(String) }
    public let text: String
    public let action: Action?
    public init(text: String, action: Action?) { self.text = text; self.action = action }

    public var actionTitle: String? {
        switch action {
        case .login: "Giriş yap"
        case .retry: "Tekrar dene"
        case .allowKeychain: "İzin ver"
        case .openApp(let n): "\(n)'u aç"
        case nil: nil
        }
    }

    public static let offline = AIIssue(text: "İnternet bağlantısı yok. Bağlantı gelince kendiliğinden yenilenir.", action: nil)

    public static func from(_ error: AIFetchError, provider: AIProviderID, cursorInstalled: Bool = true) -> AIIssue {
        let name = provider.name
        switch error {
        case .offline: return .offline
        case .notInstalled: return AIIssue(text: "\(name) bu Mac'te bulunamadı.", action: nil)
        case .needsPermission:
            return AIIssue(text: "Claude Code oturumunu okumak için macOS bir kez Mac parolanı isteyecek. Her Zaman İzin Ver'i seç.",
                           action: .allowKeychain)
        case .expired:
            switch provider {
            case .cursor: return AIIssue(text: "Cursor oturumunun süresi dolmuş. Cursor'u bir kez açman yeterli.", action: .openApp("Cursor"))
            case .claude:
                return AIIssue(text: "Claude Code oturumunun süresi dolmuş. Bir kez giriş yap; bağlantıyı bundan sonra uygulama kendisi yeniler.",
                               action: .login)
            case .codex: return AIIssue(text: "Codex oturumunun süresi dolmuş.", action: .retry)
            }
        case .needsLogin:
            switch provider {
            case .claude, .codex: return AIIssue(text: "\(name) bağlı değil. Bir kez giriş yapman yeterli.", action: .login)
            case .cursor:
                return cursorInstalled
                    ? AIIssue(text: "Cursor'da oturum açık değil. Cursor'u açıp giriş yap.", action: .openApp("Cursor"))
                    : AIIssue(text: "Cursor oturumu yok. cursor.com hesabınla giriş yap.", action: .login)
            }
        case .http(let code):
            return AIIssue(text: "\(name) şu an yanıt vermiyor (HTTP \(code)). Birazdan tekrar denenecek.", action: .retry)
        case .badResponse:
            return AIIssue(text: "\(name) verisi okunamadı. Birazdan tekrar denenecek.", action: .retry)
        }
    }
}

public struct AIProviderUsage: Equatable, Sendable {
    public var limits: [AILimit] = []
    public var state: AIProviderState = .loading
    public var plan: String?
    public var updatedAt: Date?     // son başarılı okuma
    public var note: String?        // ad altındaki ek bilgi (Cursor: "$15,60 / $20")
    public var issue: AIIssue?      // veri alınamadıysa ipucu (limitler eski haliyle kalır)
    public init() {}

    /// Eski veri: okuma hata verdi ya da 10 dakikadır yeni veri gelmedi.
    public func isStale(at now: Date = Date()) -> Bool {
        !limits.isEmpty && (issue != nil || (updatedAt.map { now.timeIntervalSince($0) > 600 } ?? false))
    }

    /// Sıralama için: sağlayıcının en dolu limiti (veri yoksa -1).
    public func worst(at now: Date = Date()) -> Double { limits.map { $0.percent(at: now) }.max() ?? -1 }

    public var isConnected: Bool {
        if case .ok = state { return true }
        return !limits.isEmpty
    }
}

/// Her limitin son yüzdesi ve en son ne zaman arttığı (bellekte): ön yüzde "son kullanılan modelin" limitini seçmek için.
public struct AIUsageHistory: Equatable, Sendable {
    private var entries: [String: (percent: Double, increasedAt: TimeInterval)] = [:]
    public init() {}

    public static func == (a: AIUsageHistory, b: AIUsageHistory) -> Bool {
        a.entries.count == b.entries.count && a.entries.allSatisfy { b.entries[$0.key]?.percent == $0.value.percent && b.entries[$0.key]?.increasedAt == $0.value.increasedAt }
    }

    public mutating func record(_ limits: [AILimit], at now: Date = Date()) {
        for l in limits {
            let old = entries[l.id]
            let increased = old.map { l.percent(at: now) > $0.percent + 0.01 } ?? false
            entries[l.id] = (l.percent(at: now), increased ? now.timeIntervalSince1970 : (old?.increasedAt ?? 0))
        }
    }

    public func lastIncrease(_ id: String) -> TimeInterval { entries[id]?.increasedAt ?? 0 }
}

public enum AIFront {
    /// Kartta (en fazla) iki halka: 1) en kısa pencere, 2) genel limit ile son kullanılan modelin limitinden dolu olan.
    /// %90'ı geçen limit, seçilmemişse ikinci sıraya zorla girer.
    public static func limits(_ limits: [AILimit], history: AIUsageHistory, at now: Date = Date()) -> [AILimit] {
        let general = limits.filter { $0.model == nil }
        guard let first = (general.isEmpty ? limits : general)
            .min(by: { ($0.window ?? .infinity) < ($1.window ?? .infinity) }) else { return [] }
        let rest = limits.filter { $0.id != first.id }
        var picked = [first]
        let generalRest = rest.first { $0.model == nil }
        let recent = rest.filter { $0.model != nil && $0.model != AILimit.unnamed }
            .max { history.lastIncrease($0.id) < history.lastIncrease($1.id) }
        if let second = [generalRest, recent].compactMap({ $0 }).max(by: { $0.percent(at: now) < $1.percent(at: now) }) { picked.append(second) }
        if let critical = limits.filter({ $0.percent(at: now) >= 90 && !picked.map(\.id).contains($0.id) })
            .max(by: { $0.percent(at: now) < $1.percent(at: now) }) {
            picked = [picked[0], critical]
        }
        return picked
    }
}

/// Yenileme takvimi: panel açılınca veri 60 sn'den eskiyse, normalde 5 dk, %75+ ise 1 dk.
public enum AIRefreshPolicy {
    public static func shouldRefreshOnOpen(lastRefresh: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastRefresh) > 60
    }

    /// Dakikalık zamanlayıcıda: bir limit %75+ ya da yenilenmişse 55 sn, değilse 295 sn geçtiyse yenile.
    public static func isDue(lastRefresh: Date, busy: Bool, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastRefresh) >= (busy ? 55 : 295)
    }

    public static func isBusy(_ usages: [AIProviderUsage], at now: Date = Date()) -> Bool {
        usages.contains { $0.worst(at: now) >= 75 || $0.limits.contains { $0.didReset(at: now) } }
    }

    /// Sağlayıcıya iki istek arası en az süre (Claude'un usage adresi sık sorulunca 429'a düşüyor).
    public static func minGap(_ p: AIProviderID) -> TimeInterval { p == .claude ? 180 : 20 }

    /// HTTP 429 sonrası bekleme: 150 sn'den başlar, her 429'da ikiye katlanır (en çok 30 dk).
    public static func nextBackoff(after current: TimeInterval?) -> TimeInterval { min((current ?? 150) * 2, 1800) }
}

/// %75 / %90 eşiği: pencere başına bir kez. Kayıt: "sıfırlanma epoch sn:bildirilen seviye".
public enum AIThreshold {
    public struct Outcome: Equatable, Sendable {
        public let record: String
        /// 0 = bildirim yok, 75 ya da 90.
        public let notify: Int
    }

    public static func evaluate(percent: Double, resetsAt: Date?, saved: String?) -> Outcome {
        let level = percent >= 90 ? 90 : percent >= 75 ? 75 : 0
        let parts = (saved ?? "").split(separator: ":").compactMap { Double($0) }
        let savedReset = parts.count == 2 ? parts[0] : nil
        let reset = resetsAt?.timeIntervalSince1970
        // Pencere sıfırlanma anıyla tanınır; 1 saate kadar fark aynı pencere (sağlayıcı anı her okumada kaydırabiliyor).
        let sameWindow: Bool
        if let reset, let savedReset, savedReset > 0 { sameWindow = abs(reset - savedReset) < 3600 }
        else { sameWindow = savedReset != nil }
        let notified = sameWindow ? Int(parts[1]) : 0
        let stamp = reset ?? (sameWindow ? savedReset ?? 0 : 0)
        return Outcome(record: "\(Int(stamp)):\(max(level, notified))", notify: level > notified ? level : 0)
    }
}

/// Türkçe süre metinleri.
public enum AIText {
    public static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let d = total / 86_400, h = (total % 86_400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d) g \(h) sa" }
        if h > 0 { return "\(h) sa \(m) dk" }
        return "\(m) dk"
    }

    /// "2 saatte", "40 dakikada", "3 günde"
    public static func within(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        if total >= 86_400 { return "\(total / 86_400) günde" }
        if total >= 3600 { return "\(total / 3600) saatte" }
        return "\(max(total / 60, 1)) dakikada"
    }

    /// Sadece en büyük birim: "12 sa", "3 g", "40 dk"
    public static func short(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        if total >= 86_400 { return "\(total / 86_400) g" }
        if total >= 3600 { return "\(total / 3600) sa" }
        return "\(max(total / 60, 1)) dk"
    }
}

// MARK: Tel biçimi (docs/protokol.md bölüm 12)

public struct AIWireLimit: Codable, Equatable, Sendable {
    public var id: String
    public var ad: String
    public var yuzde: Int
    public var sifirlanma: Int?
    public var genel: Bool
    public var tukenme: Int?
    public init(id: String, ad: String, yuzde: Int, sifirlanma: Int? = nil, genel: Bool, tukenme: Int? = nil) {
        self.id = id; self.ad = ad; self.yuzde = yuzde; self.sifirlanma = sifirlanma; self.genel = genel; self.tukenme = tukenme
    }
}

public struct AIWireProvider: Codable, Equatable, Sendable {
    public var id: String
    /// Hesap başına benzersiz: yerel hesapta sağlayıcı adı, ek hesapta UUID.
    public var hesapId: String
    /// Kullanıcının verdiği hesap adı (tek hesapta yok).
    public var hesap: String?
    public var ad: String
    public var plan: String?
    public var not: String?
    public var sorun: String?
    public var guncel: Int?
    public var limitler: [AIWireLimit]
    public init(id: String, hesapId: String? = nil, hesap: String? = nil, ad: String, plan: String? = nil, not: String? = nil,
                sorun: String? = nil, guncel: Int? = nil, limitler: [AIWireLimit]) {
        self.id = id; self.hesapId = hesapId ?? id; self.hesap = hesap; self.ad = ad; self.plan = plan; self.not = not; self.sorun = sorun; self.guncel = guncel; self.limitler = limitler
    }

    public init(provider: AIProviderID, accountId: String? = nil, accountName: String? = nil, usage: AIProviderUsage, at now: Date = Date()) {
        self.init(
            id: provider.rawValue, hesapId: accountId, hesap: accountName, ad: provider.name, plan: usage.plan, not: usage.note, sorun: usage.issue?.text,
            guncel: usage.updatedAt.map { Int($0.timeIntervalSince1970) },
            limitler: usage.limits.map { l in
                AIWireLimit(id: l.id, ad: l.label, yuzde: min(100, max(0, Int(l.percent(at: now).rounded()))),
                            sifirlanma: l.resetsAt.map { Int($0.timeIntervalSince1970) }, genel: l.model == nil,
                            tukenme: l.timeToFull(at: now).map { Int($0 / 60) * 60 })   // dakikaya yuvarlanır: gereksiz değişim olmasın
            })
    }
}
