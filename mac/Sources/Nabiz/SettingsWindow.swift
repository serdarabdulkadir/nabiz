// Ayarlar penceresi: kendi NSWindow'u; sekme hapi baslik cubuguna gomulur (trafik isiklarinin yaninda).
import SwiftUI
import AppKit

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static let toolbarDelegate = TabToolbarDelegate()

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Nabız Ayarları"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            // Bos arac cubugu + .unified: baslik cubugu ~52 pt olur, trafik isiklari dikeyde ortalanir;
            // sekme hapi da ayni satirda ortalanir (referans uygulamadaki gibi).
            let tb = NSToolbar(identifier: "nabiz.settings")
            tb.delegate = toolbarDelegate
            tb.displayMode = .iconOnly
            tb.allowsUserCustomization = false
            w.toolbar = tb
            w.titlebarSeparatorStyle = .none
            w.toolbarStyle = .unified
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Arac cubuguna sekme hapini tek oge olarak koyar; tiklamalar AppKit uzerinden SwiftUI'ye gecer.
@MainActor
final class TabToolbarDelegate: NSObject, NSToolbarDelegate {
    private static let pill = NSToolbarItem.Identifier("nabiz.tabs")

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.pill else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        let host = NSHostingView(rootView: SettingsTabPill())
        host.frame.size = host.fittingSize
        item.view = host
        item.isBordered = false
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.pill] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.pill] }
}
