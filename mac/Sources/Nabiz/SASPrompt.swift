// Eslesme istegi: telefon ilk kez baglaninca ekranin ortasinda kendiliginden acilan kucuk pencere.
// Kullanici menu cubugu panelini acmadan kodu karsilastirip onaylar.
import SwiftUI
import AppKit

@MainActor
enum SASPrompt {
    private static var panel: NSPanel?

    static func show(code: String) {
        hide()
        let view = SASPromptView(code: code, phoneName: PhoneModel.shared.phoneName) { accepted in
            PhoneModel.shared.confirmSAS(accepted: accepted)
            hide()
        }
        .preferredColorScheme(.dark)
        let host = NSHostingController(rootView: view)
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 250),
                        styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentViewController = host
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.center()
        p.orderFrontRegardless()
        p.makeKey()
        NSSound(named: "Glass")?.play()
        panel = p
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct SASPromptView: View {
    let code: String
    let phoneName: String?
    let decide: (Bool) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "smartphone")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Telefon eşleşmek istiyor")
                .font(.system(size: 15, weight: .semibold))
            Text(code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code)
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .accessibilityLabel("Kod \(code.map(String.init).joined(separator: " "))")
            Text("Telefonda aynı kod görünüyorsa onayla.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Reddet") { decide(false) }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
                Button("Onayla") { decide(true) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .frame(width: 340)
    }
}
