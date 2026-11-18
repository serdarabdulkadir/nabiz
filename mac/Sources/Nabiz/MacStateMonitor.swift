// Mac kilit / ekran / uyku durumu. Degisince PhoneModel'e bildirir (mac.state, docs/protokol.md bolum 7).
import AppKit
import CoreGraphics

@MainActor
final class MacStateMonitor {
    static let shared = MacStateMonitor()

    private(set) var locked = false
    private(set) var screenOff = false
    var onChange: ((_ locked: Bool, _ screenOff: Bool, _ sleeping: Bool) -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        if let d = CGSessionCopyCurrentDictionary() as? [String: Any] {
            locked = (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
        }
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = true; self?.fire(false) }
        }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked = false; self?.fire(false) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenOff = true; self?.fire(false) }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenOff = false; self?.fire(false) }
        }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(true) }
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenOff = false; self?.fire(false) }
        }
    }

    private func fire(_ sleeping: Bool) {
        onChange?(locked, screenOff, sleeping)
        // Uyku oncesi: baglanti kuyrugu ana kuyruk; cerceve yazilsin diye run loop'u kisaca dondur (en cok ~300 ms).
        if sleeping { RunLoop.current.run(until: Date().addingTimeInterval(0.3)) }
    }
}
