// Bildirim izni reddedilmisse acilista gosterilen kucuk pencere.
// macOS reddedilen izni uygulamanin yeniden sormasina izin vermez; tek yol Sistem Ayarlari.
import SwiftUI
import AppKit

@MainActor
enum NotifPrompt {
    static let skipKey = "notif.prompt.skip"
    private static var panel: NSPanel?

    /// Nabiz'in bildirim ayar sayfasini dogrudan acar (yoksa genel Bildirimler bolumu).
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.nabiz.mac"
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                    "x-apple.systempreferences:com.apple.Notifications-Settings.extension"]
        for s in urls { if let u = URL(string: s), NSWorkspace.shared.open(u) { return } }
    }

    static func showIfNeeded() {
        guard panel == nil, !UserDefaults.standard.bool(forKey: skipKey) else { return }
        let view = NotifPromptView(
            open: { openSystemSettings(); hide() },
            later: { hide() },
            never: { UserDefaults.standard.set(true, forKey: skipKey); hide() }
        )
        .preferredColorScheme(.dark)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 230),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentViewController = NSHostingController(rootView: view)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.center()
        p.orderFrontRegardless()
        panel = p
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct NotifPromptView: View {
    let open: () -> Void
    let later: () -> Void
    let never: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Bildirimler kapalı").font(.headline)
            Text("Pil, depolama ve bağlantı uyarıları için Sistem Ayarları'nda Nabız bildirimlerine izin ver.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: later) { pill("Sonra") }
                Button(action: open) { pill("Sistem Ayarları", strong: true) }
            }
            .buttonStyle(PressableStyle())
            Button("Bir daha sorma", action: never)
                .buttonStyle(.plain).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 340)
    }

    private func pill(_ text: String, strong: Bool = false) -> some View {
        Text(text).font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(strong ? Color.primary.opacity(0.14) : Color.clear, in: Capsule())
            .glassCapsule(interactive: true)
    }
}
