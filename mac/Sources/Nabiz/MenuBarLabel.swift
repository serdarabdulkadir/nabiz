// Menu cubugu ogesi: MenuBarExtra etiketi yalniz Text/Image destekler; ozel cizim ImageRenderer ile NSImage olur.
// Kirmizi yoksa sablon goruntu (sistem rengi), varsa sablon degil ve renkler menu cubugu gorunumune gore secilir.
import SwiftUI
import AppKit
import NabizCore

@MainActor
final class RenderCache {
    var key = ""
    var image: NSImage?
}

struct MenuBarLabel: View {
    var model: MonitorModel
    private var phone = PhoneModel.shared
    private var prefs = BarPrefs()
    @Environment(\.colorScheme) private var scheme
    @State private var cache = RenderCache()

    init(model: MonitorModel) { self.model = model }

    var body: some View {
        let state = BarState.make(prefs: prefs, snapshot: model.snapshot,
                                  phone: phone.isConnected ? phone.snapshot : nil, history: model.cpuHistory.values)
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let template = !state.hasCritical
        let key = state.key + "|\(template)|\(dark)|\(scheme)"
        if let image = image(for: state, key: key, template: template, dark: dark) {
            Image(nsImage: image)
        } else {
            Image(systemName: "waveform.path.ecg")
        }
    }

    private func image(for state: BarState, key: String, template: Bool, dark: Bool) -> NSImage? {
        if cache.key != key || cache.image == nil {
            cache.image = render(state, template: template, dark: dark)
            cache.key = key
        }
        return cache.image
    }

    private func render(_ state: BarState, template: Bool, dark: Bool) -> NSImage? {
        let ink: Color = template ? .black : (dark ? .white : .black)
        let renderer = ImageRenderer(content: MenuBarArt(state: state, ink: ink, alert: .red))
        renderer.scale = 2
        guard let img = renderer.nsImage else { return nil }
        img.isTemplate = template
        return img
    }
}
