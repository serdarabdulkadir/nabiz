// Menu cubugu uygulamasi: Dock simgesi yok, MenuBarExtra(.window); ayarlar kendi penceresinde (SettingsWindow).
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AlertCenter.shared.start(); MonitorModel.shared.start(); PhoneModel.shared.start(); AIStore.shared.start(); AktarModel.shared.start()
            if CommandLine.arguments.contains("--ayarlar") { SettingsWindow.show() }
        }
    }
}

@main
struct NabizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = MonitorModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
                .preferredColorScheme(.dark)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
