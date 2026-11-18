// Panel karolari: halka karo, cekirdek cubuklari, satir.
import SwiftUI
import NabizCore

struct TileTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary)
    }
}

/// Halka gostergesi (54 pt, 5 pt cizgi). fraction nil ise bos halka ve "--".
struct RingTile: View {
    let title: String
    let fraction: Double?
    let value: String
    var detail: String? = nil
    var critical = false
    var warning = false
    var bolt = false

    private var tint: Color { Palette.tint(critical: critical, warning: warning) }

    var body: some View {
        VStack(spacing: 6) {
            TileTitle(text: title)
            ZStack {
                Circle().stroke(Palette.track, lineWidth: 5)
                Circle()
                    // Bos degerde yuvarlak uc nokta cizmesin: hic dolum yoksa tamamen gizle.
                    .trim(from: 0, to: CGFloat(min(1, max(0, fraction ?? 0))))
                    .stroke(AngularGradient(colors: [tint.opacity(0.7), tint], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .opacity((fraction ?? 0) > 0.001 ? 1 : 0)
                    .animation(Motion.ring, value: fraction)
                HStack(spacing: 1) {
                    if bolt { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Palette.charging) }
                    Text(value).roundedDigits(size: 13)
                        .foregroundStyle(tint)
                        .contentTransition(.numericText(value: (fraction ?? 0) * 100))
                        .animation(.smooth, value: value)
                }
            }
            .frame(width: 54, height: 54)
            Text(detail ?? " ").font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassTile()
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var critical = false
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(critical ? Palette.critical : Color.primary)
                .contentTransition(.numericText()).animation(.smooth, value: value)
        }
        .font(.callout)
    }
}

/// Cekirdek basina dikey cubuk; P ve E gruplari ayri baslikla.
struct CoreBars: View {
    let cpu: CPUStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TileTitle(text: "Çekirdekler")
            if let cpu, !cpu.cores.isEmpty {
                let groups = split(cpu)
                ForEach(groups, id: \.title) { g in
                    VStack(alignment: .leading, spacing: 3) {
                        if let t = g.title.isEmpty ? nil : g.title {
                            Text(t).font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(g.values.enumerated()), id: \.offset) { _, v in
                                CoreBar(value: v)
                            }
                        }
                    }
                }
            } else {
                Text(Format.missing).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: Radius.group)
    }

    private struct Group { var title: String; var values: [Int] }

    /// Apple Silicon'da host_processor_info once verimlilik (E), sonra performans (P) cekirdeklerini verir.
    private func split(_ cpu: CPUStats) -> [Group] {
        if let p = cpu.perfCores, let e = cpu.effCores, p + e == cpu.cores.count, p > 0, e > 0 {
            return [Group(title: "Performans (\(p))", values: Array(cpu.cores[e...])),
                    Group(title: "Verimlilik (\(e))", values: Array(cpu.cores[..<e]))]
        }
        return [Group(title: "", values: cpu.cores)]
    }
}

/// Dar dikey cubuk: iz + alttan yukselen dolum. >= %75 turuncu, >= %90 kirmizi.
private struct CoreBar: View {
    let value: Int
    private let height: CGFloat = 28
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let tint: Color = value >= 90 ? Palette.critical : (value >= 75 ? Palette.warning : Color.primary.opacity(0.85))
        shape.fill(Palette.track)
            .frame(height: height)
            .overlay(alignment: .bottom) {
                shape.fill(tint)
                    .frame(height: max(3, height * CGFloat(min(100, max(0, value))) / 100))
                    .animation(Motion.ring, value: value)
            }
            .clipShape(shape)
    }
}

// MARK: Gecmis grafigi

/// Alan dolgulu (%15) cizgi; son nokta vurgulu. xs/ys 0...1; x = zaman (sagda simdi).
struct AreaLine: View {
    let points: [CGPoint]
    var tint: Color = .primary
    var showsDot = true

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let mapped = points.map { CGPoint(x: $0.x * size.width, y: size.height - $0.y * size.height) }
            var line = Path()
            line.move(to: mapped[0])
            for p in mapped.dropFirst() { line.addLine(to: p) }
            var area = line
            area.addLine(to: CGPoint(x: mapped.last!.x, y: size.height))
            area.addLine(to: CGPoint(x: mapped[0].x, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(tint.opacity(0.15)))
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            if showsDot, let l = mapped.last {
                ctx.fill(Path(ellipseIn: CGRect(x: l.x - 3, y: l.y - 3, width: 6, height: 6)), with: .color(tint))
            }
        }
    }
}

/// "Son 10 dk": CPU ve bellek sparkline + ag icin ince ikili cizgi. Veri yoksa gizli.
struct HistoryTile: View {
    let points: [HistoryPoint]

    var body: some View {
        if points.count >= 2 {
            let end = points.last!.ts
            let span = MonitorModel.historySeconds
            let x: (HistoryPoint) -> CGFloat = { CGFloat(max(0, min(1, 1 - (end - $0.ts) / span))) }
            VStack(alignment: .leading, spacing: 8) {
                TileTitle(text: "Son 10 dk")
                HStack(spacing: 10) {
                    series("CPU", points.compactMap { p in p.cpu.map { (p, Double($0) / 100) } }, x: x)
                    series("Bellek", points.compactMap { p in p.mem.map { (p, $0) } }, x: x)
                }
                netLines(x: x)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassTile(cornerRadius: Radius.group)
        }
    }

    private func series(_ title: String, _ data: [(HistoryPoint, Double)], x: (HistoryPoint) -> CGFloat) -> some View {
        let last = data.last?.1
        let tint = Palette.tint(critical: (last ?? 0) >= 0.9, warning: (last ?? 0) >= Thresholds.warning)
        return VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            AreaLine(points: data.map { CGPoint(x: x($0.0), y: min(1, max(0, $0.1))) }, tint: tint)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func netLines(x: (HistoryPoint) -> CGFloat) -> some View {
        let down = points.compactMap { p in p.down.map { (p, Double($0)) } }
        let up = points.compactMap { p in p.up.map { (p, Double($0)) } }
        let peak = max(1024, (down + up).map(\.1).max() ?? 0)
        if down.count >= 2 {
            VStack(alignment: .leading, spacing: 3) {
                Text("Ağ ↓ ↑").font(.caption2).foregroundStyle(.secondary)
                ZStack {
                    AreaLine(points: down.map { CGPoint(x: x($0.0), y: $0.1 / peak) }, tint: .primary, showsDot: false)
                    AreaLine(points: up.map { CGPoint(x: x($0.0), y: $0.1 / peak) }, tint: Color.primary.opacity(0.5), showsDot: false)
                }
                .frame(height: 18)
            }
        }
    }
}

// MARK: Surecler ve cihazlar

struct ProcessList: View {
    let processes: [ProcessUsage]
    var body: some View {
        if !processes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                TileTitle(text: "Süreçler")
                ForEach(processes, id: \.pid) { p in
                    HStack {
                        Text(p.name).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text("%\(Int(p.percent.rounded()))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassTile(cornerRadius: Radius.group)
        }
    }
}

struct DeviceList: View {
    let devices: [DeviceBattery]
    var body: some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                TileTitle(text: "Cihazlar")
                ForEach(devices, id: \.name) { d in
                    HStack {
                        Text(d.name).font(.caption).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text("%\(d.percent)")
                            .font(.caption2.weight(.medium)).monospacedDigit()
                            .foregroundStyle(d.percent <= 20 ? Palette.critical : Color.primary)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Palette.fill, in: Capsule(style: .continuous))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassTile(cornerRadius: Radius.group)
        }
    }
}
