// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi.
import Foundation
import NabizCore

/// Codex limitleri: Codex CLI'nin kullandığı endpoint, CLI'nin kendi token'ı ile (GET /backend-api/wham/usage).
/// Ayrıştırma NabizCore.AIParse.codex.
enum CodexProvider {
    static var home: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    /// Codex CLI bu Mac'te oturum açmış mı (auth.json var mı)?
    static var isLoggedIn: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path) }

    static func fetch() async throws -> (plan: String?, limits: [AILimit]) {
        guard let authData = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let auth = try? JSONSerialization.jsonObject(with: authData) as? [String: Any],
              let tokens = auth["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String
        else { throw AIFetchError.needsLogin }
        return try await fetch(access: access, accountID: tokens["account_id"] as? String)
    }

    /// wham/usage verilen token'la (Codex CLI'nin kendi token'ı; Nabız saklamaz, yenilemez)
    static func fetch(access: String, accountID: String?) async throws -> (plan: String?, limits: [AILimit]) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let account = accountID { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.timeoutInterval = 20
        let (body, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw AIFetchError.needsLogin }
        guard status == 200 else { throw AIFetchError.http(status) }
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw AIFetchError.badResponse }
        return AIParse.codex(root)
    }
}
