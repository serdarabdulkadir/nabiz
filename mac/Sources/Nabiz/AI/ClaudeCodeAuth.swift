// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi.
import Foundation
import Security
import LocalAuthentication
import NabizCore

/// Claude kullanımını Claude Code'un kendi oturumundan okur (giriş gerekmez):
/// ~/.claude/.credentials.json ya da Anahtar Zinciri'ndeki "Claude Code-credentials" ->
/// GET api.anthropic.com/api/oauth/usage. Token yalnızca okunur; yenilenmez ve hiçbir yere yazılmaz.
/// Anahtar Zinciri okuması macOS'tan kullanıcı izni ister (Nabız kendi anahtarları için Anahtar Zinciri kullanmaz).
enum ClaudeCodeAuth {
    private static let service = "Claude Code-credentials"
    private static let userAgent: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Nabiz/\(v)"
    }()

    @MainActor private static var cached: (token: String, expires: Date?, plan: String?)?

    /// Claude Code bu Mac'te oturum açmış mı? (Anahtar Zinciri'ne parola okumadan bakar; soru çıkmaz)
    static var isAvailable: Bool {
        if FileManager.default.fileExists(atPath: credentialsFile.path) { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: silentContext(),
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Soru çıkarmayan bağlam (izin yoksa errSecInteractionNotAllowed döner).
    private static func silentContext() -> LAContext {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        return ctx
    }

    /// Eski tip (dosya tabanlı) Anahtar Zinciri kayıtları bağlamı yok sayıp izin penceresi açabilir; süreç genelinde
    /// etkileşimi kapatmak için SecKeychainSetUserInteractionAllowed (kullanımdan kaldırıldı, bu yüzden dlsym ile).
    nonisolated private static func setKeychainInteraction(_ allowed: Bool) {
        typealias Fn = @convention(c) (DarwinBoolean) -> OSStatus
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecKeychainSetUserInteractionAllowed") else { return }
        _ = unsafeBitCast(sym, to: Fn.self)(DarwinBoolean(allowed))
    }

    private static var credentialsFile: URL {
        let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return base.appendingPathComponent(".credentials.json")
    }

    /// Kullanım JSON'u ve plan adı. `allowPrompt`: kullanıcı "İzin ver"e bastıysa macOS sorusu çıkabilir.
    @MainActor
    static func fetchUsage(allowPrompt: Bool) async throws -> (plan: String?, data: Data) {
        let creds = try await credentials(allowPrompt: allowPrompt)
        let (data, status) = try await usage(creds.token)
        if status == 401 { cached = nil; throw AIFetchError.expired }
        guard status == 200 else { throw AIFetchError.http(status) }
        return (creds.plan, data)
    }

    /// api.anthropic.com/api/oauth/usage (Claude Code'un kendi token'ı; Nabız saklamaz, yenilemez)
    static func usage(_ token: String) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    @MainActor
    private static func credentials(allowPrompt: Bool) async throws -> (token: String, expires: Date?, plan: String?) {
        if let cached, (cached.expires ?? .distantFuture) > Date().addingTimeInterval(60) { return cached }

        let raw: Data
        if let file = try? Data(contentsOf: credentialsFile) {
            raw = file
        } else {
            // Ana iş parçacığı dışında: izin penceresi açıkken panel donmasın
            let (status, data) = await Task.detached { readKeychain(allowPrompt: allowPrompt) }.value
            switch status {
            case errSecSuccess: raw = data ?? Data()
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled: throw AIFetchError.needsPermission
            default: throw AIFetchError.notInstalled
            }
        }

        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { throw AIFetchError.notInstalled }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        if let expires, expires < Date() { throw AIFetchError.expired }
        let plan = (oauth["subscriptionType"] as? String)?.capitalized
        let result = (token, expires, plan)
        cached = result
        return result
    }

    /// Eski tip (dosya tabanlı) giriş Anahtar Zinciri kSecUseAuthenticationUIFail'i yok sayıp izin penceresi açabilir ve
    /// çağrıyı bekletir. Sormadan okumada etkileşim süreç genelinde kapatılır; izin yoksa hemen errSecInteractionNotAllowed döner.
    nonisolated private static func readKeychain(allowPrompt: Bool) -> (OSStatus, Data?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        if !allowPrompt {
            query[kSecUseAuthenticationContext as String] = silentContext()
            setKeychainInteraction(false)
        }
        defer { if !allowPrompt { setKeychainInteraction(true) } }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }
}
