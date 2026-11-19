// "Son kullanılan" sağlayıcı için yalnız OKUMA: aracın kendi kayıtlarının değişim zamanı (diske yazılmaz).
import Foundation
import NabizCore

enum AILocalActivity {
    /// Sağlayıcının yerel araç kayıtlarının en yeni değişim zamanı (epoch sn); yoksa 0.
    static func lastUsed(_ id: AIProviderID) -> TimeInterval {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths: [URL]
        switch id {
        case .claude:
            let base = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude")
            paths = [base.appendingPathComponent("history.jsonl"), base.appendingPathComponent("projects")]
        case .codex:
            paths = [CodexProvider.home.appendingPathComponent("history.jsonl"), CodexProvider.home.appendingPathComponent("sessions")]
        case .cursor:
            paths = [CursorProvider.databaseURL]
        }
        return paths.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .map(\.timeIntervalSince1970).max() ?? 0
    }
}
