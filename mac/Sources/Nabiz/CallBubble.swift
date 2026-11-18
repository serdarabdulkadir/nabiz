// Yuzen arama baloncugu (ORBIO FloatingCallBubble'dan): arama surerken ekranin sag ustunde, surukle-birak kapsul.
// Cagri yonetimi izni yoksa dugmesiz yalniz bilgi gosterir. Bitince 2 sn "Arama bitti".
import AppKit
import SwiftUI
import Observation
import NabizCore

@MainActor @Observable
final class BubbleModel {
    var call = CallState(durum: .bosta)
    var startedAt: Date?
    var ended = false
    var visible = false
}

private struct CallBubbleView: View {
    let bubble: BubbleModel
    let phone: PhoneModel
    let open: () -> Void
    let dragChanged: () -> Void
    let dragEnded: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var call: CallState { bubble.call }
    private var contact: ContactRecord? { phone.contact(for: call.numara) }
    private var title: String { contact?.ad ?? call.kisiAdi ?? call.numara ?? "Bilinmeyen numara" }
    private var ringing: Bool { call.durum == .caliyor && call.yon == .gelen && !bubble.ended }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ContactAvatar(record: contact, name: call.kisiAdi ?? call.numara, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    subtitle.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { _ in dragChanged() }
                .onEnded { _ in dragEnded() })
            buttons
        }
        .padding(.horizontal, 12)
        .frame(width: 300, height: 64)
        .glassTile(cornerRadius: 32)
        .scaleEffect(reduceMotion ? 1 : (bubble.visible ? 1 : 0.9))
        .opacity(bubble.visible ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : Motion.spring, value: bubble.visible)
    }

    @ViewBuilder
    private var subtitle: some View {
        if bubble.ended {
            Text("Arama bitti")
        } else {
            switch call.durum {
            case .araniyor: Text("Arıyor…")
            case .caliyor: Text("Çalıyor")
            case .acik:
                if let start = bubble.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let t = max(0, Int(ctx.date.timeIntervalSince(start)))
                        Text(String(format: "%02d:%02d", t / 60, t % 60)).monospacedDigit()
                    }
                } else {
                    Text("Görüşme sürüyor")
                }
            case .bosta: Text("")
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if bubble.ended || !phone.perm.cagriYonetimi {
            EmptyView()
        } else if ringing {
            round("phone.down.fill", Palette.critical, "Reddet") { phone.reject() }
            round("phone.fill", Palette.charging, "Yanıtla") { phone.answer() }
        } else {
            round("phone.down.fill", Palette.critical, "Bitir") { phone.hangup() }
        }
    }

    private func round(_ symbol: String, _ color: Color, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Circle().fill(color)).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

@MainActor
final class CallBubbleController {
    static let shared = CallBubbleController()

    private static let positionKey = "aramaBaloncuguKonum"
    private static let size = NSSize(width: 300, height: 64)
    private static let margin: CGFloat = 16

    private let model = BubbleModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?

    /// Arama / izin / baglanti degisince cagrilir: aramayi gosterir, bittiyse 2 sn sonra kapatir.
    func update() {
        let phone = PhoneModel.shared
        let enabled = UserDefaults.standard.object(forKey: SettingsKey.phoneCallBubble) as? Bool ?? true
        let active = phone.isConnected && phone.callState.durum != .bosta
        if active && enabled {
            hideTask?.cancel(); hideTask = nil
            model.call = phone.callState
            model.startedAt = phone.callStartedAt
            model.ended = false
            if !(panel?.isVisible ?? false) || !model.visible { show() }
        } else if panel?.isVisible ?? false, model.visible {
            if phone.isConnected && enabled {
                guard hideTask == nil else { return }
                model.ended = true
                scheduleHide(after: 2)
            } else {
                hideTask?.cancel()
                scheduleHide(after: 0)   // baglanti koptu / ayar kapali: "bitti" gostermeden kapat
            }
        }
    }

    private func scheduleHide(after seconds: Double) {
        hideTask = Task { [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled, let self else { return }
            self.model.visible = false
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
            self.hideTask = nil
        }
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(initialOrigin())
        panel.orderFrontRegardless()
        Task { @MainActor [model] in model.visible = true }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = CallBubbleView(bubble: model, phone: PhoneModel.shared,
                                  open: { PhoneWindow.show(.aramalar) },
                                  dragChanged: { [weak self] in self?.dragChanged() },
                                  dragEnded: { [weak self] in self?.dragEnded() })
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.size)
        p.contentView = host
        return p
    }

    // MARK: Konum

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func initialOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.dictionary(forKey: Self.positionKey) as? [String: Double],
           let x = saved["x"], let y = saved["y"] {
            return clamp(NSPoint(x: x, y: y), snap: false)
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.frame ?? visible
        let y = min(frame.maxY - 44 - Self.size.height, visible.maxY - Self.size.height - 4)
        return NSPoint(x: visible.maxX - Self.size.width - Self.margin, y: y)
    }

    /// Ekran sinirinda sikistirir; `snap` ise kenara 24 pt yakinsa kenar bosluguna yaslar.
    private func clamp(_ origin: NSPoint, snap: Bool) -> NSPoint {
        let center = NSPoint(x: origin.x + Self.size.width / 2, y: origin.y + Self.size.height / 2)
        let visible = screen(containing: center)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let minX = visible.minX, maxX = visible.maxX - Self.size.width
        let minY = visible.minY, maxY = visible.maxY - Self.size.height
        var x = min(max(origin.x, minX), maxX), y = min(max(origin.y, minY), maxY)
        if snap {
            let m = Self.margin
            if x - minX < 24 { x = minX + m } else if maxX - x < 24 { x = maxX - m }
            if y - minY < 24 { y = minY + m } else if maxY - y < 24 { y = maxY - 4 }
        }
        return NSPoint(x: x, y: y)
    }

    private func dragChanged() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if dragStartOrigin == nil { dragStartOrigin = panel.frame.origin; dragStartMouse = mouse }
        guard let o = dragStartOrigin, let m = dragStartMouse else { return }
        panel.setFrameOrigin(NSPoint(x: o.x + mouse.x - m.x, y: o.y + mouse.y - m.y))
    }

    private func dragEnded() {
        defer { dragStartOrigin = nil; dragStartMouse = nil }
        guard let panel else { return }
        let target = clamp(panel.frame.origin, snap: true)
        panel.animator().setFrameOrigin(target)
        UserDefaults.standard.set(["x": Double(target.x), "y": Double(target.y)], forKey: Self.positionKey)
    }
}
