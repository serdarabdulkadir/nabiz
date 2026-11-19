// Kaynak: AI Limit Tracker (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md). Nabız AlertCenter üzerinden çalışır.
import Foundation
import NabizCore

/// Limit %75 / %90'ı geçince pencere başına bir kez, yüksek kullanılan limit sıfırlanınca "yenilendi" bildirimi.
/// YALNIZCA genel limitler (model == nil); modele özel ve kod adlı sayaçlar sessiz. Eşik mantığı NabizCore.AIThreshold.
@MainActor
enum AINotifier {
    private static func isOn(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static func process(provider: String, limits: [AILimit]) {
        for limit in limits {
            guard limit.model == nil else {
                AlertCenter.shared.aiCancelPending(ids: ["reset.\(limit.id)"])
                continue
            }
            checkThreshold(provider: provider, limit: limit)
            scheduleReset(provider: provider, limit: limit)
        }
    }

    private static func checkThreshold(provider: String, limit: AILimit) {
        let defaults = UserDefaults.standard
        let key = "ai.notify.level.\(limit.id)"
        let percent = limit.percent()
        let outcome = AIThreshold.evaluate(percent: percent, resetsAt: limit.resetsAt, saved: defaults.string(forKey: key))
        defaults.set(outcome.record, forKey: key)
        // Kapalı türün bildirimi gönderilmez; eşik yine kaydedilir ki açınca eskiler birden gelmesin
        guard outcome.notify > 0, isOn(outcome.notify == 90 ? SettingsKey.aiNotify90 : SettingsKey.aiNotify75) else { return }
        var body = outcome.notify == 90 ? "Limite çok yaklaştın." : "Limitin dörtte üçünü kullandın."
        if let reset = limit.resetsAt { body += " \(AIText.countdown(reset.timeIntervalSinceNow)) sonra sıfırlanır." }
        AlertCenter.shared.aiNotify(id: "level.\(limit.id)", title: "\(provider) · \(limit.label) %\(Int(percent.rounded()))", body: body)
    }

    /// "Yenilendi" bildirimi sıfırlanma anına zamanlanır (uygulamanın yenilemesini beklemez).
    private static func scheduleReset(provider: String, limit: AILimit) {
        let id = "reset.\(limit.id)"
        guard isOn(SettingsKey.aiNotifyReset), limit.percent() >= 75, let reset = limit.resetsAt, reset.timeIntervalSinceNow > 0 else {
            AlertCenter.shared.aiCancelPending(ids: [id])
            return
        }
        AlertCenter.shared.aiSchedule(id: id, title: "\(provider) · \(limit.label) limitin yenilendi",
                                      body: "Kaldığın yerden devam edebilirsin.", after: reset.timeIntervalSinceNow + 30)
    }
}
