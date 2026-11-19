// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi:
// Her hesap ayrı kart; yerel hesap aracın kendi kaydından okunur, ek hesaplar web girişiyle. Nabız token saklamaz ve yenilemez;
// durum bellekte, diske yalnız hesap listesi (ad, id, sağlayıcı, e-posta) yazılır.
import AppKit
import WebKit
import NabizCore

/// Sağlayıcı kullanım durumları ve yenileme. Takvim ve ayrıştırma mantığı NabizCore'da (AIRefreshPolicy, AIParse).
@MainActor @Observable
final class AIStore {
    static let shared = AIStore()

    /// hesap id -> durum
    private(set) var usage: [String: AIProviderUsage] = [:]
    private(set) var accounts: [AIAccount] = AIAccountList.merged(saved: AIStore.loadSaved())
    private(set) var enabledSet: Set<AIProviderID> = []
    private(set) var lastUpdated: Date?
    private(set) var pending = 0
    private(set) var history = AIUsageHistory()
    /// Veri ya da açık sağlayıcılar değişti (telefona ai.state yollamak için).
    /// Sağlayıcının yerel araç kayıtlarından okunan son kullanım (yalnız okuma, bellekte).
    private(set) var localUsed: [AIProviderID: TimeInterval] = [:]
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var sessions: [String: WebSession] = [:]
    @ObservationIgnored private var backoff: [String: (until: Date, step: TimeInterval)] = [:]
    @ObservationIgnored private var lastRequest: [String: Date] = [:]
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false

    enum Trigger { case scheduled, manual, immediate }

    var isRefreshing: Bool { pending > 0 }
    var enabled: [AIProviderID] { AIProviderID.allCases.filter { enabledSet.contains($0) } }
    var hasEnabled: Bool { !enabledSet.isEmpty }

    // MARK: Hesaplar

    private static func loadSaved() -> [AIAccount] {
        UserDefaults.standard.data(forKey: "ai.accounts").flatMap { try? JSONDecoder().decode([AIAccount].self, from: $0) } ?? []
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(AIAccountList.persisted(accounts)) { UserDefaults.standard.set(data, forKey: "ai.accounts") }
        onChange?()
    }

    func accounts(for id: AIProviderID) -> [AIAccount] { AIAccountList.accounts(for: id, in: accounts) }
    func usage(of account: AIAccount) -> AIProviderUsage { usage[account.id] ?? AIProviderUsage() }
    func title(_ account: AIAccount) -> String { AIAccountList.title(account, in: accounts) }
    func label(_ account: AIAccount) -> String { AIAccountList.label(account, in: accounts) }

    /// Kartlarda görünen hesaplar: ek hesap varken verisi olmayan yerel gizlenir.
    func visibleAccounts(_ id: AIProviderID) -> [AIAccount] {
        AIAccountList.visible(id, in: accounts) { !usage(of: $0).limits.isEmpty }
    }

    /// Panel sırası: sağlayıcı sırası, içinde yerel önce. Her hesap ayrı kart.
    var cards: [AIAccount] { enabled.flatMap { visibleAccounts($0) } }

    /// Görünen verinin en eskisi ("Güncellendi" şeridi).
    var dataUpdated: Date? { cards.compactMap { usage(of: $0).updatedAt }.min() ?? lastUpdated }

    func start() {
        guard !started else { return }
        started = true
        if let saved = UserDefaults.standard.stringArray(forKey: SettingsKey.aiEnabled) {
            enabledSet = Set(saved.compactMap(AIProviderID.init(rawValue:)))
        } else {
            enabledSet = Set(AIProviderID.allCases.filter(Self.isDetected))
        }
        if hasEnabled { refresh() }
        // Dakikada bir bakılır: normalde 5 dk'da, bir limit %75'i geçtiyse her dakika yenilenir
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.hasEnabled else { return }
                let busy = AIRefreshPolicy.isBusy(self.cards.map { self.usage(of: $0) })
                if AIRefreshPolicy.isDue(lastRefresh: self.lastRefresh, busy: busy) { self.refresh() }
            }
        }
    }

    /// Bu Mac'te kurulu / oturumu olan sağlayıcılar (varsayılan açık olanlar).
    static func isDetected(_ id: AIProviderID) -> Bool {
        switch id {
        case .claude: ClaudeCodeAuth.isAvailable
        case .codex: CodexProvider.isLoggedIn
        case .cursor: CursorProvider.isInstalled
        }
    }

    func setEnabled(_ id: AIProviderID, _ on: Bool) {
        if on { enabledSet.insert(id) } else { enabledSet.remove(id) }
        UserDefaults.standard.set(enabled.map(\.rawValue), forKey: SettingsKey.aiEnabled)
        if on { Task { await loadAll(id); lastUpdated = Date(); onChange?() } }
        else {
            AlertCenter.shared.aiCancelPending(ids: accounts(for: id).flatMap { usage(of: $0).limits }.map { "reset.\($0.id)" })
            onChange?()
        }
    }

    // MARK: Yenileme

    /// Panel açılınca: veri 60 sn'den eskiyse hemen yenile.
    func refreshIfStale() {
        guard hasEnabled, AIRefreshPolicy.shouldRefreshOnOpen(lastRefresh: lastRefresh) else { return }
        refresh()
    }

    /// manual: Yenile düğmesi; 429 sonrası bekleme süresini bir kez atlar.
    func refresh(manual: Bool = false) {
        guard pending == 0 else { return }
        lastRefresh = Date()
        for id in enabled {
            for account in accounts(for: id) {
                pending += 1
                Task {
                    defer { pending -= 1 }
                    await load(account, trigger: manual ? .manual : .scheduled)
                    lastUpdated = Date()
                    onChange?()
                }
            }
        }
    }

    private func loadAll(_ id: AIProviderID) async {
        await withTaskGroup(of: Void.self) { group in
            for account in accounts(for: id) { group.addTask { await self.load(account, trigger: .immediate) } }
        }
    }

    func reload(_ account: AIAccount, allowPrompt: Bool = false) {
        Task { await load(account, allowPrompt: allowPrompt, trigger: .immediate); lastUpdated = Date(); onChange?() }
    }

    /// Kartın ipucundaki düzeltme.
    func perform(_ action: AIIssue.Action, for account: AIAccount) {
        switch action {
        case .login: login(account)
        case .allowKeychain: reload(account, allowPrompt: true)
        case .openApp(let name):
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/\(name).app"), configuration: NSWorkspace.OpenConfiguration())
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.refresh() }   // uygulama açılınca veri gelsin
        case .retry: refresh(manual: true)
        }
    }

    /// Yerel hesap: araç varsa aracın kendi girişi (tarayıcıda); yoksa web penceresi. Ek hesap: her zaman web penceresi.
    func login(_ account: AIAccount) {
        if account.isLocal, ToolLogin.isAvailable(account.provider) { toolLogin(account.provider) } else { webLogin(account) }
    }

    /// Aracın kendi girişi (claude auth login / codex login): araç kendi kaydına yazar, Nabız oradan okur.
    func toolLogin(_ id: AIProviderID) {
        let account = AIAccount.local(id)
        Task {
            guard await ToolLogin.shared.start(id) else { return }
            backoff[account.id] = nil
            await load(account, trigger: .immediate)
            lastUpdated = Date()
            onChange?()
        }
    }

    /// claude.ai / chatgpt.com / cursor.com giriş penceresi (hesabın kendi çerez kutusunda).
    func webLogin(_ account: AIAccount) {
        let s = session(for: account)
        s.onLoginWindowClosed = { [weak self] in self?.reload(account) }
        s.showLogin()
    }

    // MARK: Hesap ekle / adlandır / kaldır

    /// Yeni ek hesap: ayrı çerez kutusunda giriş penceresi. Pencere kapanınca veri gelirse eklenir; gelmezse (giriş yapılmadı)
    /// hesap eklenmez ve kutu silinir; aynı e-posta reddedilir.
    func addAccount(_ provider: AIProviderID) {
        let account = AIAccount(id: UUID().uuidString, provider: provider)
        let s = session(for: account)
        s.onLoginWindowClosed = { [weak self] in Task { await self?.finishAdding(account) } }
        s.showLogin(title: "Yeni \(provider.name) hesabı · \(provider.webHost) girişi")
    }

    private func finishAdding(_ account: AIAccount) async {
        guard let s = sessions[account.id] else { return }
        do {
            let result = try await s.fetch()
            if let email = result.email,
               AIAccountList.isDuplicate(email: email, provider: account.provider, in: accounts, localEmail: Self.localEmail(account.provider)) {
                discard(account)
                duplicateAlert(email)
                return
            }
            var added = account
            added.email = result.email
            accounts.append(added)
            saveAccounts()
            s.onLoginWindowClosed = { [weak self] in self?.reload(added) }
            apply(result, to: added)
            lastUpdated = Date()
            onChange?()
        } catch {
            discard(account)
        }
    }

    private func duplicateAlert(_ email: String) {
        let alert = NSAlert()
        alert.messageText = "Bu hesap zaten ekli"
        alert.informativeText = "\(email) bu listede var. Başka bir hesapla giriş yapmak için Hesap ekle'yi tekrar dene."
        alert.runModal()
    }

    func rename(_ account: AIAccount, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[i].name = name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name
        saveAccounts()
    }

    /// Ek hesabı kaldırır: çerez kutusu silinir, bekleyen bildirimleri iptal edilir.
    func remove(_ account: AIAccount) {
        guard !account.isLocal else { return }
        AlertCenter.shared.aiCancelPending(ids: usage(of: account).limits.map { "reset.\($0.id)" })
        accounts.removeAll { $0.id == account.id }
        usage[account.id] = nil
        saveAccounts()
        discard(account)
    }

    /// Oturumu bırakır ve çerez kutusunu siler (WKWebView serbest kaldıktan sonra).
    private func discard(_ account: AIAccount) {
        sessions[account.id] = nil
        guard let storeID = account.storeID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { try? await WKWebsiteDataStore.remove(forIdentifier: storeID) }
        }
    }

    private func session(for account: AIAccount) -> WebSession {
        if let s = sessions[account.id] { return s }
        let s: WebSession
        if let storeID = account.storeID { s = WebSession(provider: account.provider, dataStore: WKWebsiteDataStore(forIdentifier: storeID)) }
        else { s = WebSession(provider: account.provider) }
        sessions[account.id] = s
        return s
    }

    /// Yerel oturumun e-postası (dosyalardan, ağsız); yinelenen hesabı yakalamak için.
    private static func localEmail(_ provider: AIProviderID) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch provider {
        case .claude:
            guard ClaudeCodeAuth.isAvailable, let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return (root["oauthAccount"] as? [String: Any])?["emailAddress"] as? String
        case .codex:
            guard let data = try? Data(contentsOf: CodexProvider.home.appendingPathComponent("auth.json")),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jwt = (root["tokens"] as? [String: Any])?["id_token"] as? String else { return nil }
            return AIParse.jwtClaims(jwt)?["email"] as? String
        case .cursor: return CursorProvider.cachedEmail
        }
    }

    // MARK: Okuma

    private func load(_ account: AIAccount, allowPrompt: Bool = false, trigger: Trigger = .scheduled) async {
        let id = account.provider, key = account.id
        let sinceLast = lastRequest[key].map { Date().timeIntervalSince($0) } ?? .infinity
        let gap = AIRefreshPolicy.minGap(id)
        // 429 beklemesi: Yenile bir kez deneyebilir, ama güvenli aralık geçtiyse
        if let wait = backoff[key], wait.until > Date(), !(trigger == .manual && sinceLast >= gap) { return }
        if trigger != .immediate, sinceLast < gap { return }
        lastRequest[key] = Date()
        do {
            apply(try await fetch(account, allowPrompt: allowPrompt), to: account)
            backoff[key] = nil
        } catch AIFetchError.http(429) {
            let step = AIRefreshPolicy.nextBackoff(after: backoff[key]?.step)
            backoff[key] = (Date().addingTimeInterval(step), step)
            // Eski veri kalır, uyarı çıkmaz; veri hiç yoksa kısa bir not
            var current = usage(of: account)
            if current.limits.isEmpty {
                let issue = AIIssue(text: "\(id.name) kısa süreliğine sınır koydu; birkaç dakika içinde tekrar denenecek.", action: nil)
                current.issue = issue; current.state = .error(issue.text)
                usage[key] = current
            }
        } catch {
            let mapped = Self.map(error)
            var current = usage(of: account)
            current.issue = AIIssue.from(mapped, provider: id, cursorInstalled: CursorProvider.isInstalled)
            if !account.isLocal, mapped == .needsLogin { current.issue = AIIssue(text: "\(label(account)) oturumu kapanmış.", action: .login) }
            if mapped == .needsLogin, current.limits.isEmpty { current.state = .needsLogin }
            else if current.limits.isEmpty { current.state = .error(current.issue?.text ?? "") }
            usage[key] = current
        }
    }

    private static func map(_ error: Error) -> AIFetchError {
        if let e = error as? AIFetchError { return e }
        if let url = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed].contains(url.code) { return .offline }
        return .badResponse
    }

    private func apply(_ result: WebSession.Result, to account: AIAccount) {
        var current = usage(of: account)
        // Ek hesapların limit kimlikleri öneklenir: bildirim ve "son kullanılan" kayıtları ayrışır
        let limits = AIAccountList.prefixed(result.limits, for: account)
        current.limits = limits
        current.note = result.note
        if result.plan != nil { current.plan = result.plan }
        current.state = .ok
        current.issue = nil
        current.updatedAt = Date()
        usage[account.id] = current
        history.record(limits)
        if account.isLocal { localUsed[account.provider] = AILocalActivity.lastUsed(account.provider) }
        AINotifier.process(provider: title(account), limits: limits)
        if let email = result.email, email != account.email, let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i].email = email
            saveAccounts()
        }
    }

    /// Okuma kaynağı. Ek hesap: kendi web oturumu. Yerel hesap: aracın kendi kaydı (Claude Code Anahtar Zinciri, ~/.codex/auth.json,
    /// Cursor uygulaması), olmazsa / düşmüşse web oturumu. Token saklanmaz ve yenilenmez.
    private func fetch(_ account: AIAccount, allowPrompt: Bool) async throws -> WebSession.Result {
        let web = session(for: account)
        guard account.isLocal else { return try await web.fetch() }
        switch account.provider {
        case .claude:
            guard ClaudeCodeAuth.isAvailable else { return try await web.fetch() }
            do {
                let (plan, data) = try await ClaudeCodeAuth.fetchUsage(allowPrompt: allowPrompt)
                return WebSession.Result(plan: plan, limits: AIParse.claude(data), email: nil)
            } catch let error as URLError {
                throw error
            } catch {
                if let result = try? await web.fetch() { return result }
                // Mac parolası sormak yerine aracın kendi girişi
                if case AIFetchError.needsPermission = error, !allowPrompt, ToolLogin.isAvailable(.claude) { throw AIFetchError.needsLogin }
                throw error
            }
        case .codex:
            guard CodexProvider.isLoggedIn else { return try await web.fetch() }
            do {
                let r = try await CodexProvider.fetch()
                return WebSession.Result(plan: r.plan, limits: r.limits, email: nil)
            } catch let error as URLError {
                throw error
            } catch {
                if let result = try? await web.fetch() { return result }
                throw error
            }
        case .cursor:
            guard CursorProvider.isInstalled else { return try await web.fetch() }
            do {
                let r = try await CursorProvider.fetch()
                return WebSession.Result(plan: r.plan, note: r.note, limits: r.limits, email: nil)
            } catch let error as URLError {
                throw error
            } catch {
                if let result = try? await web.fetch() { return result }
                throw error
            }
        }
    }

    // MARK: Menü çubuğu

    /// Sağlayıcının son kullanımı: artış gözlemi ve yerel araç kayıtlarının değişim zamanından yenisi.
    func lastUsed(_ id: AIProviderID) -> TimeInterval {
        let seen = accounts(for: id).flatMap { usage(of: $0).limits }.map { history.lastIncrease($0.id) }.max() ?? 0
        return max(seen, localUsed[id] ?? 0)
    }

    private func hasLiveData(_ account: AIAccount) -> Bool {
        let u = usage(of: account)
        return !u.limits.isEmpty && u.issue?.action != .login && u.issue?.action != .allowKeychain
    }

    /// Sütun değeri: en son kullanılan hesabın 5 saatlik limiti. 5 saatlik penceresi olmayan sağlayıcı (Cursor) yalnızca
    /// başka aday yoksa görünür; hiç kullanım kaydı yoksa sağlayıcı sırasındaki ilk hesap.
    var recentShortLimit: AILimit? {
        let candidates = cards.compactMap { account -> (limit: AILimit, used: TimeInterval)? in
            guard hasLiveData(account), let short = AIFront.limits(usage(of: account).limits, history: history).first else { return nil }
            return (short, max(usage(of: account).limits.map { history.lastIncrease($0.id) }.max() ?? 0, localUsed[account.provider] ?? 0))
        }
        let fiveHour = candidates.filter { ($0.limit.window ?? .infinity) <= 6 * 3600 }
        return (fiveHour.isEmpty ? candidates : fiveHour).max { $0.used < $1.used }?.limit
    }

    /// Menü çubuğu sütunu: yüzde (veri yoksa nil, sütun görünmez).
    var barPercent: Double? { recentShortLimit?.percent() }

    /// Menü çubuğu simgesi girdileri: verisi olan sağlayıcılar, her biri en boş hesabıyla. Veri yoksa boş.
    func menuEntries(style: AIBarStyle) -> [AIMenuIcon.Entry] {
        enabled.compactMap { id in
            let live = visibleAccounts(id).filter { hasLiveData($0) }
            guard let account = live.min(by: { usage(of: $0).worst() < usage(of: $1).worst() }) else { return nil }
            let limits = usage(of: account).limits
            let limit = style == .mostFull ? limits.max { $0.percent() < $1.percent() } : AIFront.limits(limits, history: history).first
            return AIMenuIcon.Entry(provider: id, percent: limit?.percent(), resetsAt: limit?.resetsAt, lastUsed: lastUsed(id))
        }
    }

    // MARK: Telefona

    /// ai.state yükü: "Telefonda göster" kapalıysa ya da hiçbiri açık/bağlı değilse boş dizi.
    func wireProviders() -> [AIWireProvider] {
        guard UserDefaults.standard.object(forKey: SettingsKey.aiShowOnPhone) as? Bool ?? true else { return [] }
        let now = Date()
        return cards.compactMap { account in
            let u = usage(of: account)
            guard u.isConnected || u.issue != nil else { return nil }
            let multi = accounts(for: account.provider).count > 1
            return AIWireProvider(provider: account.provider, accountId: account.id,
                                  accountName: multi ? label(account) : nil, usage: u, at: now)
        }
    }
}
