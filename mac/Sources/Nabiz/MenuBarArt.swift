// Menu cubugu cizimi: veri (BarState) + stil gorunumleri (MenuBarArt). Etiket bunu NSImage'a cevirir,
// ayarlar onizlemeleri ayni gorunumu dogrudan cizer.
import SwiftUI
import NabizCore

/// Ayar anahtarlari: etiket ve onizlemeler ayni degerleri okur.
struct BarPrefs: DynamicProperty {
    @AppStorage(BarModule.cpu.key) private var cpu = true
    @AppStorage(BarModule.ram.key) private var ram = true
    @AppStorage(BarModule.disk.key) private var disk = false
    @AppStorage(BarModule.battery.key) private var battery = false
    @AppStorage(BarModule.network.key) private var network = false
    @AppStorage(BarModule.gpu.key) private var gpu = false
    @AppStorage(BarModule.phone.key) private var phone = false
    @AppStorage(BarModule.ai.key) private var ai = true
    @AppStorage(MenuBarKey.aiStyle) var aiStyle: AIBarStyle = .column
    @AppStorage(MenuBarKey.style) var style: MenuBarStyle = .metin
    @AppStorage(MenuBarKey.showPercent) var showPercent = true
    @AppStorage(MenuBarKey.critical) var criticalRed = true

    func isOn(_ m: BarModule) -> Bool {
        switch m {
        case .cpu: cpu
        case .ram: ram
        case .disk: disk
        case .battery: battery
        case .network: network
        case .gpu: gpu
        case .phone: phone
        case .ai: ai
        }
    }
}

struct BarItem: Equatable, Identifiable {
    let module: BarModule
    let label: String       // iki satir stilinin ust etiketi
    let letter: String
    let fraction: Double?
    let value: String
    let critical: Bool
    let excess: Double      // kritikse esigi asma orani (tek simge secimi icin)
    var id: BarModule { module }
    var key: String { "\(module.rawValue)|\(value)|\(critical)|\(Int((fraction ?? -1) * 100))" }
}

struct BarState {
    var items: [BarItem]
    var style: MenuBarStyle
    var showPercent: Bool
    var history: [Int]
    /// AI simgesi (sütun stili dışındaki stiller): menü çubuğu öğesinin sonuna çizilir.
    var aiEntries: [AIMenuIcon.Entry] = []
    var aiStyle: AIBarStyle = .column
    var hasCritical: Bool { items.contains { $0.critical } || aiEntries.contains { ($0.percent ?? 0) >= 90 } }

    /// Yeniden cizim anahtari: degismediyse onceki NSImage yeniden kullanilir.
    var key: String {
        var k = "\(style.rawValue)|\(showPercent)|" + items.map(\.key).joined(separator: ",")
        if !aiEntries.isEmpty { k += "|ai:\(aiStyle.rawValue):" + aiEntries.map(\.key).joined(separator: ",") }
        if style == .grafik, items.contains(where: { $0.module == .cpu }) {
            k += "|" + history.map(String.init).joined(separator: ",")
        }
        return k
    }

    @MainActor
    static func make(prefs: BarPrefs, style: MenuBarStyle? = nil, snapshot s: Snapshot?, phone: Snapshot?, history: [Int]) -> BarState {
        var st = BarState(items: items(prefs: prefs, snapshot: s, phone: phone), style: style ?? prefs.style,
                          showPercent: prefs.showPercent, history: history)
        if prefs.isOn(.ai), prefs.aiStyle != .column {
            st.aiEntries = AIStore.shared.menuEntries(style: prefs.aiStyle)
            st.aiStyle = prefs.aiStyle
        }
        return st
    }

    private static func frac(_ used: UInt64, _ total: UInt64) -> Double { total > 0 ? Double(used) / Double(total) : 0 }

    @MainActor
    static func items(prefs: BarPrefs, snapshot s: Snapshot?, phone: Snapshot?) -> [BarItem] {
        let red = prefs.criticalRed
        var out: [BarItem] = []
        for m in BarModule.allCases where prefs.isOn(m) {
            switch m {
            case .cpu:
                let v = s?.cpu?.total
                let c = red && (v ?? 0) >= 85
                out.append(BarItem(module: m, label: "CPU", letter: "C", fraction: v.map { Double($0) / 100 },
                                   value: Format.percent(v), critical: c, excess: c ? Double(v ?? 0) / 85 : 0))
            case .ram:
                let f = s?.mem.map { frac($0.used, $0.total) }
                let c = red && s?.mem?.pressure == "critical"
                out.append(BarItem(module: m, label: "RAM", letter: "R", fraction: f,
                                   value: Format.percent(fraction: f), critical: c, excess: c ? 2 : 0))
            case .disk:
                let f = s?.disk.map { frac($0.used, $0.total) }
                let c = red && (f ?? 0) >= 0.9
                out.append(BarItem(module: m, label: "DİSK", letter: "D", fraction: f,
                                   value: Format.percent(fraction: f), critical: c, excess: c ? (f ?? 0) / 0.9 : 0))
            case .battery:
                guard let b = s?.battery else { continue }   // masaustunde pil yok
                let c = red && b.level <= 20 && !b.charging
                out.append(BarItem(module: m, label: "PİL", letter: "P", fraction: Double(b.level) / 100,
                                   value: Format.percent(b.level), critical: c, excess: c ? 20 / Double(max(b.level, 1)) : 0))
            case .network:
                let d = s?.net?.down, u = s?.net?.up
                var text = Format.missing
                var f: Double?
                if let d, let u {
                    let down = d >= u
                    let v = down ? d : u
                    text = (down ? "↓" : "↑") + Format.bytes(v)
                    f = min(1, log10(1 + Double(v)) / 8)   // 0..100 MB/s, logaritmik (yalniz dolgu)
                }
                out.append(BarItem(module: m, label: "AĞ", letter: "A", fraction: f, value: text, critical: false, excess: 0))
            case .gpu:
                let v = s?.gpu
                out.append(BarItem(module: m, label: "GPU", letter: "G", fraction: v.map { Double($0) / 100 },
                                   value: Format.percent(v), critical: false, excess: 0))
            case .ai:
                // Yalnız "sütun" stilinde; diğer stiller simge olarak sona çizilir (make). Veri yoksa görünmez.
                guard prefs.aiStyle == .column, let v = AIStore.shared.barPercent else { continue }
                let c = red && v >= 90
                out.append(BarItem(module: m, label: "AI", letter: "AI", fraction: v / 100, value: Format.percent(Int(v.rounded())),
                                   critical: c, excess: c ? v / 90 : 0))
            case .phone:
                guard let b = phone?.battery else { continue }
                let c = red && b.level <= 20 && !b.charging
                out.append(BarItem(module: m, label: "TEL", letter: "T", fraction: Double(b.level) / 100,
                                   value: Format.percent(b.level), critical: c, excess: c ? 20 / Double(max(b.level, 1)) : 0))
            }
        }
        return out
    }
}

struct MenuBarArt: View {
    let state: BarState
    let ink: Color
    let alert: Color

    var body: some View {
        HStack(spacing: 6) {
            if !state.items.isEmpty || state.aiEntries.isEmpty { content }
            if !state.aiEntries.isEmpty {
                Image(nsImage: AIMenuIcon.image(state.aiEntries, style: state.aiStyle, label: NSColor(ink)))
            }
        }
        .frame(height: 22)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if state.items.isEmpty {
            Image(systemName: "waveform.path.ecg").font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
        } else {
            switch state.style {
            case .metin: metin
            case .ikiSatir: ikiSatir
            case .halkalar: halkalar
            case .barlar: barlar
            case .grafik: grafik
            case .tekSimge: tekSimge
            }
        }
    }

    private func color(_ it: BarItem) -> Color { it.critical ? alert : ink }

    /// Harf (ya da telefon simgesi); ag modulunde yok.
    @ViewBuilder
    private func tag(_ it: BarItem, size: CGFloat) -> some View {
        switch it.module {
        case .phone: Image(systemName: "smartphone").font(.system(size: size, weight: .medium))
        case .network: EmptyView()
        default: Text(it.letter).opacity(0.75)
        }
    }

    private var metin: some View {
        HStack(spacing: 5) {
            ForEach(Array(state.items.enumerated()), id: \.element.id) { i, it in
                if i > 0 { Text("·").foregroundStyle(ink.opacity(0.5)) }
                HStack(spacing: 2) { tag(it, size: 12); Text(it.value) }.foregroundStyle(color(it))
            }
        }
        .font(.system(size: 13, weight: .medium)).monospacedDigit()
    }

    private var ikiSatir: some View {
        HStack(spacing: 7) {
            ForEach(state.items) { it in
                VStack(spacing: 0) {
                    Group {
                        if it.module == .phone {
                            Image(systemName: "smartphone").font(.system(size: 7.5, weight: .semibold))
                        } else {
                            Text(it.label).font(.system(size: 7.5, weight: .semibold))
                        }
                    }
                    .opacity(0.7)
                    Text(it.value).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                }
                .foregroundStyle(color(it))
            }
        }
    }

    private var halkalar: some View {
        HStack(spacing: 6) {
            ForEach(state.items) { it in
                HStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(color(it).opacity(0.25), lineWidth: 2)
                        Circle().trim(from: 0, to: CGFloat(min(1, max(0, it.fraction ?? 0))))
                            .stroke(color(it), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if it.module == .phone {
                            Image(systemName: "smartphone").font(.system(size: 7, weight: .bold))
                        } else {
                            Text(it.letter).font(.system(size: 7.5, weight: .bold))
                        }
                    }
                    .frame(width: 16, height: 16)
                    if state.showPercent { Text(it.value).font(.system(size: 10.5, weight: .medium)).monospacedDigit() }
                }
                .foregroundStyle(color(it))
            }
        }
    }

    private var barlar: some View {
        HStack(spacing: 6) {
            ForEach(state.items) { it in
                HStack(spacing: 2.5) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(color(it).opacity(0.25))
                        Capsule().fill(color(it)).frame(height: max(2, 14 * CGFloat(min(1, max(0, it.fraction ?? 0)))))
                    }
                    .frame(width: 4, height: 14)
                    if it.module == .phone {
                        Image(systemName: "smartphone").font(.system(size: 8, weight: .bold))
                    } else {
                        Text(it.letter).font(.system(size: 8.5, weight: .bold))
                    }
                    if state.showPercent { Text(it.value).font(.system(size: 10.5, weight: .medium)).monospacedDigit() }
                }
                .foregroundStyle(color(it))
            }
        }
    }

    private var grafik: some View {
        HStack(spacing: 6) {
            ForEach(state.items) { it in
                HStack(spacing: 3) {
                    if it.module == .cpu {
                        Sparkline(values: state.history, tint: color(it)).frame(width: 36, height: 16)
                        if state.showPercent { Text(it.value).font(.system(size: 10.5, weight: .medium)).monospacedDigit() }
                    } else {
                        tag(it, size: 9).font(.system(size: 10.5, weight: .medium))
                        Text(it.value).font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                    }
                }
                .foregroundStyle(color(it))
            }
        }
    }

    private var tekSimge: some View {
        let pick = state.items.filter(\.critical).max { $0.excess < $1.excess }
            ?? state.items.first { $0.module == .cpu } ?? state.items[0]
        return HStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg").font(.system(size: 13, weight: .medium))
            if state.showPercent {
                HStack(spacing: 2) {
                    if pick.module != .cpu { tag(pick, size: 10) }
                    Text(pick.value)
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
        }
        .foregroundStyle(color(pick))
    }
}

/// Alan grafigi: 30 slot, sag hizali, 0...100 sabit olcek.
struct Sparkline: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = values.count
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i + 30 - n) / 29, y: h - h * CGFloat(min(100, max(0, v))) / 100)
            }
            ZStack {
                if let first = pts.first, let last = pts.last, n > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: h))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: last.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(tint.opacity(0.3))
                    Path { p in
                        p.move(to: first)
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                } else {
                    Path { p in p.move(to: CGPoint(x: 0, y: h - 0.5)); p.addLine(to: CGPoint(x: w, y: h - 0.5)) }
                        .stroke(tint.opacity(0.4), lineWidth: 1)
                }
            }
        }
    }
}

/// Ayarlar onizlemesi: guncel degerlerle, secili stilden bagimsiz verilen stilde.
struct LiveBarArt: View {
    let style: MenuBarStyle
    private var prefs = BarPrefs()
    init(style: MenuBarStyle) { self.style = style }

    var body: some View {
        let phone = PhoneModel.shared
        let st = BarState.make(prefs: prefs, style: style, snapshot: MonitorModel.shared.snapshot,
                               phone: phone.isConnected ? phone.snapshot : nil,
                               history: MonitorModel.shared.cpuHistory.values)
        MenuBarArt(state: st, ink: .white, alert: .red)
    }
}
