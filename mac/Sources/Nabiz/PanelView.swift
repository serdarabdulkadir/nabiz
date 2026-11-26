// Panel: 344 pt, ustte "Bu Mac | Telefon | Aktar" hap secici.
import SwiftUI
import NabizCore

private enum PanelTab: String, CaseIterable {
    case mac = "Bu Mac"
    case phone = "Telefon"
    case aktar = "Aktar"
    case ai = "AI"
}

struct PanelView: View {
    var model: MonitorModel
    @State private var tab: PanelTab = .mac
    @State private var dropTargeted = false
    private let ai = AIStore.shared
    private let aktar = AktarModel.shared

    /// AI sekmesi yalniz modul acik ve en az bir saglayici aciksa gorunur.
    private var showAI: Bool { PanelModule.ai.isOn && ai.hasEnabled }
    private var tabs: [PanelTab] { PanelTab.allCases.filter { ($0 != .ai || showAI) && ($0 != .aktar || aktar.enabled) } }

    var body: some View {
        VStack(spacing: 10) {
            picker
            // Yalniz secili sekme yukseklige katki verir; pencerenin ust kenari PanelChrome'da sabit tutulur.
            CappedScroll {
                ZStack(alignment: .top) {
                    switch shown {
                    case .mac:
                        MacTab(snapshot: model.snapshot, model: model)
                            .transition(.directional(forward: false))
                    case .phone:
                        PhoneTab(phone: PhoneModel.shared)
                            .transition(.directional(forward: true))
                    case .aktar:
                        AktarTab()
                            .transition(.directional(forward: true))
                    case .ai:
                        AITab()
                            .transition(.directional(forward: true))
                    }
                }
            }
            footer
        }
        .animation(Motion.spring, value: shown)
        .padding(12)
        .frame(width: 344)
        .panelChrome()
        // Dosya birakma: hangi sekmede olursa olsun Aktar'a gider.
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard aktar.enabled, !files.isEmpty else { return false }
            tab = .aktar
            aktar.send(files)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted && aktar.enabled {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .strokeBorder(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(4).allowsHitTesting(false)
            }
        }
        .onAppear { model.panelOpen = true; AIStore.shared.refreshIfStale() }
        .onDisappear { model.panelOpen = false }
    }

    /// Secili sekme gizlenmisse (AI / Aktar kapatildi) Bu Mac'e doner.
    private var shown: PanelTab { tabs.contains(tab) ? tab : .mac }

    private var picker: some View {
        SlidingPillPicker(options: tabs, selection: shown, title: \.rawValue) { tab = $0 }
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

/// Icerik ekranin gorunur yuksekligini asmadikca aynen cizilir; asarsa kaydirilabilir olur.
private struct CappedScroll<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    private var limit: CGFloat { max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 150) }

    var body: some View {
        let measured = content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        if height > limit {
            ScrollView(.vertical, showsIndicators: false) { measured }.frame(height: limit)
        } else {
            measured
        }
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
            if PanelModule.history.isOn { HistoryTile(points: model.history.values) }
            VStack(spacing: 6) {
                // Pil yoksa GPU zaten dorduncu karoda.
                if s?.battery != nil { StatRow(label: "GPU", value: Format.percent(s?.gpu)) }
                StatRow(label: "Ağ ↓", value: Format.speed(s?.net?.down))
                StatRow(label: "Ağ ↑", value: Format.speed(s?.net?.up))
                if let b = s?.battery {
                    StatRow(label: "Pil", value: batteryLine(b), critical: b.level <= 20 && !b.charging)
                    StatRow(label: "Pil sağlığı / döngü", value: "\(Format.percent(b.health)) · \(b.cycles.map(String.init) ?? Format.missing)")
                }
                if PanelModule.sensors.isOn {
                    StatRow(label: "CPU sıcaklığı", value: model.extras.temperature.map { "\(Int($0.rounded())) °C" } ?? Format.missing)
                    // Fansiz Mac'te satir hic gorunmez.
                    if !model.extras.fans.isEmpty {
                        StatRow(label: model.extras.fans.count > 1 ? "Fan 1" : "Fan",
                                value: "\(model.extras.fans[0]) rpm")
                        if model.extras.fans.count > 1 {
                            StatRow(label: "Fan 2", value: "\(model.extras.fans[1]) rpm")
                        }
                    }
                }
                StatRow(label: "Çalışma süresi", value: Format.duration(seconds: s?.uptime))
            }
            .padding(12)
            .glassTile(cornerRadius: Radius.group)
            if PanelModule.processes.isOn { ProcessList(processes: model.extras.processes) }
            if PanelModule.devices.isOn { DeviceList(devices: model.devices) }
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
