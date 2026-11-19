// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız için sadeleştirildi.
import Foundation
import SQLite3
import NabizCore

/// Cursor kullanımı, Cursor uygulamasının kendi oturumundan (giriş gerekmez):
/// state.vscdb (salt okunur) içindeki cursorAuth/accessToken -> WorkosCursorSessionToken çerezi -> GET cursor.com/api/usage-summary.
/// Belgesiz uç; Cursor değiştirirse kartta ipucu çıkar, son veri kalır. Ayrıştırma NabizCore.AIParse.cursor.
enum CursorProvider {
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
            || FileManager.default.fileExists(atPath: databaseURL.path)
    }

    static func fetch() async throws -> (plan: String?, note: String?, limits: [AILimit]) {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { throw AIFetchError.notInstalled }
        guard let token = try readValue("cursorAuth/accessToken") else { throw AIFetchError.needsLogin }
        guard let user = AIParse.cursorUserID(fromJWT: token) else { throw AIFetchError.expired }

        var request = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        request.setValue("WorkosCursorSessionToken=\(user)%3A%3A\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw AIFetchError.expired }
        guard status == 200, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIFetchError.http(status)
        }
        return AIParse.cursor(root)
    }

    /// Cursor'da oturum açık hesabın e-postası (aynı hesabın ek hesap olarak eklenmesini önlemek için).
    static var cachedEmail: String? { try? readValue("cursorAuth/cachedEmail") }

    /// state.vscdb -> ItemTable[key] (salt okunur, kilit almadan)
    private static func readValue(_ key: String) throws -> String? {
        var db: OpaquePointer?
        let uri = "file:\(databaseURL.path)?mode=ro&immutable=1"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw AIFetchError.notInstalled
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?1 LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if let text = sqlite3_column_text(stmt, 0) { return String(cString: text) }
        if let blob = sqlite3_column_blob(stmt, 0) {
            return String(data: Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 0))), encoding: .utf8)
        }
        return nil
    }
}
