// Panel: 344 pt, ustte "Bu Mac | Telefon" hap secici.
import SwiftUI
import NabizCore

private enum PanelTab: String, CaseIterable {
    case mac = "Bu Mac"
    case phone = "Telefon"
}

struct PanelView: View {
    var model: MonitorModel
    @State private var tab: PanelTab = .mac

    var body: some View {
        VStack(spacing: 10) {
            picker
            // Iki sekme ust uste durur: panel yuksekligi sekme degisince oynamaz (pencere kaymaz).
            ZStack(alignment: .top) {
                MacTab(snapshot: model.snapshot, model: model)
                    .modifier(DirectionalShift(offset: -16, active: tab != .mac))
                    .allowsHitTesting(tab == .mac)
                    .accessibilityHidden(tab != .mac)
                PhoneTab(phone: PhoneModel.shared)
                    .modifier(DirectionalShift(offset: 16, active: tab != .phone))
                    .allowsHitTesting(tab == .phone)
                    .accessibilityHidden(tab != .phone)
            }
            footer
        }
        .animation(Motion.spring, value: tab)
        .padding(12)
        .frame(width: 344)
        .onAppear { model.panelOpen = true }
        .onDisappear { model.panelOpen = false }
    }

    private var picker: some View {
        SlidingPillPicker(options: PanelTab.allCases, selection: tab, title: \.rawValue) { tab = $0 }
    }

    private var footer: some View {
        HStack {
            Button("Ayarlar") { SettingsWindow.show() }
            Spacer()
            Button("Çık") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}

private struct MacTab: View {
    let snapshot: Snapshot?
    let model: MonitorModel

    var body: some View {
        let s = snapshot
        VStack(spacing: 8) {
            if let chip = model.chipName ?? model.modelName {
                HStack {
                    Text([model.modelName, model.chipName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .accessibilityLabel(chip)
            }
            GlassGroup {
                VStack(spacing: 8) {
                    HStack(spacing: 8) { cpuTile(s); memTile(s) }
                    HStack(spacing: 8) { diskTile(s); fourthTile(s) }
                }
            }
            CoreBars(cpu: s?.cpu)
            VStack(spacing: 6) {
                // Pil yoksa GPU zaten dorduncu karoda.
                if s?.battery != nil { StatRow(label: "GPU", value: Format.percent(s?.gpu)) }
                StatRow(label: "Ağ ↓", value: Format.speed(s?.net?.down))
                StatRow(label: "Ağ ↑", value: Format.speed(s?.net?.up))
                if let b = s?.battery {
                    StatRow(label: "Pil", value: batteryLine(b), critical: b.level <= 20 && !b.charging)
                    StatRow(label: "Pil sağlığı / döngü", value: "\(Format.percent(b.health)) · \(b.cycles.map(String.init) ?? Format.missing)")
                }
                StatRow(label: "Çalışma süresi", value: Format.duration(seconds: s?.uptime))
            }
            .padding(12)
            .glassTile(cornerRadius: Radius.group)
        }
    }

    private func cpuTile(_ s: Snapshot?) -> some View {
        RingTile(title: "CPU", fraction: s?.cpu.map { Double($0.total) / 100 }, value: Format.percent(s?.cpu?.total),
                 detail: s?.cpu.map { "\($0.cores.count) çekirdek" },
                 warning: (s?.cpu?.total ?? 0) >= Int(Thresholds.warning * 100))
    }

    private func memTile(_ s: Snapshot?) -> some View {
        let frac = s?.mem.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        let crit = s?.mem?.pressure == "critical"
        return RingTile(title: "Bellek", fraction: frac, value: Format.percent(fraction: frac),
                        detail: s?.mem.map { "\(Format.bytes($0.used)) / \(Format.bytes($0.total))" }, critical: crit,
                        warning: (frac ?? 0) >= Thresholds.warning)
    }

    private func diskTile(_ s: Snapshot?) -> some View {
        let frac = s?.disk.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        return RingTile(title: "Disk", fraction: frac, value: Format.percent(fraction: frac),
                        detail: s?.disk.map { "\(Format.bytes($0.total - $0.used, base: 1000)) boş" },
                        critical: (frac ?? 0) >= 0.9, warning: (frac ?? 0) >= Thresholds.warning)
    }

    @ViewBuilder
    private func fourthTile(_ s: Snapshot?) -> some View {
        if let b = s?.battery {
            RingTile(title: "Pil", fraction: Double(b.level) / 100, value: Format.percent(b.level),
                     detail: b.charging ? "Şarj oluyor" : Format.minutes(b.minutes),
                     critical: b.level <= 20 && !b.charging, bolt: b.charging)
        } else {
            RingTile(title: "GPU", fraction: s?.gpu.map { Double($0) / 100 }, value: Format.percent(s?.gpu))
        }
    }

    private func batteryLine(_ b: BatteryStats) -> String {
        let t = Format.minutes(b.minutes)
        let label = b.charging ? "dolmaya" : "kaldı"
        return t == Format.missing ? Format.percent(b.level) : "\(Format.percent(b.level)) · \(t) \(label)"
    }
}
