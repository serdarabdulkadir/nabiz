// Panel dis kosesi: sistem MenuBarExtra penceresinin kucuk yaricapi yerine eşmerkezli kendi sekli
// (dis = karo 22 + panel padding 12 = 34). Pencere hack'i basarisiz olursa sistem gorunumu kalir.
import SwiftUI
import AppKit

enum PanelShape {
    static let radius = Radius.tile + 12
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

extension View {
    @ViewBuilder
    func panelChrome() -> some View {
        let base = self.background(PanelWindowAccessor())
        if #available(macOS 26, *) {
            base
                .background { Color.clear.glassEffect(.regular, in: .rect(cornerRadius: PanelShape.radius)) }
                .clipShape(PanelShape.shape)
        } else {
            base
                .background(.regularMaterial, in: PanelShape.shape)
                .overlay(PanelShape.shape.strokeBorder(Palette.stroke, lineWidth: 0.5))
                .clipShape(PanelShape.shape)
        }
    }
}

/// MenuBarExtra penceresini saydam yapar, sistemin arka plan efekt gorunumlerini gizler.
private struct PanelWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AccessorView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class AccessorView: NSView {
        private var topY: CGFloat?
        private var adjusting = false
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            apply(window)
            observe(window)
            // Sistem gorunumleri pencere gosterilirken yeniden kurulabilir: bir kez daha uygula.
            DispatchQueue.main.async { [weak window, weak self] in
                guard let window else { return }
                self?.apply(window)
                self?.topY = Self.anchoredTop(window)
            }
        }

        /// Yukseklik degisince ust kenar sabit kalir (pencere kaymaz).
        private func observe(_ window: NSWindow) {
            guard observers.isEmpty else { return }
            let nc = NotificationCenter.default
            // Ust kenar, panel gosterildiginde sistemin koydugu yerdir (menu cubugunun hemen alti).
            observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    self.topY = Self.anchoredTop(window)
                }
            })
            observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window, !self.adjusting else { return }
                    let top = self.topY ?? Self.anchoredTop(window)
                    if abs(window.frame.maxY - top) > 0.5 {
                        self.adjusting = true
                        var f = window.frame
                        f.origin.y = top - f.height
                        window.setFrame(f, display: true)
                        self.adjusting = false
                    }
                    // Yeni boyutta golge yeniden hesaplansin (eski dikdortgen golge kalmasin).
                    DispatchQueue.main.async { window.invalidateShadow() }
                }
            })
        }

        /// Pencerenin ust kenari: mevcut konum, ama menu cubugundan 40 pt'den fazla asagi kaymissa menu cubugunun hemen alti.
        static func anchoredTop(_ window: NSWindow) -> CGFloat {
            guard let screen = window.screen ?? NSScreen.main else { return window.frame.maxY }
            let barBottom = screen.visibleFrame.maxY
            let top = window.frame.maxY
            return (top < barBottom - 40 || top > screen.frame.maxY) ? barBottom - 6 : top
        }

        private func apply(_ window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            if let frameView = window.contentView?.superview {
                hideEffectViews(in: frameView)
                clearLayers(from: frameView, window: window)
            }
            window.invalidateShadow()
        }

        private func hideEffectViews(in root: NSView) {
            for v in root.subviews {
                if let fx = v as? NSVisualEffectView {
                    fx.isHidden = true
                } else if !(v === window?.contentView) {
                    hideEffectViews(in: v)
                }
            }
        }

        /// Sistem kenar/arka plan katmanlari: saydam ve bizim yaricapimizla maskeli. Siniflar log'lanir.
        private func clearLayers(from frameView: NSView, window: NSWindow) {
            var chain: [NSView] = [frameView]
            var cur = frameView.superview
            while let v = cur { chain.append(v); cur = v.superview }
            for v in chain {
                v.wantsLayer = true
                v.layer?.backgroundColor = .clear
                v.layer?.cornerRadius = PanelShape.radius
                v.layer?.cornerCurve = .continuous
                v.layer?.masksToBounds = true
                v.layer?.borderWidth = 0
            }
            NSLog("Nabiz panel: pencere %@, katmanlar %@", String(describing: type(of: window)),
                  chain.map { String(describing: type(of: $0)) }.joined(separator: " > "))
        }
    }
}
