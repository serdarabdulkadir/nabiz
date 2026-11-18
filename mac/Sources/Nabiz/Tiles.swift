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
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Palette.track)
                                    Capsule().fill(Color.primary.opacity(0.85))
                                        .frame(height: max(3, 28 * CGFloat(v) / 100))
                                }
                                .frame(height: 28)
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
