// Panel > AI sekmesi: her hesap ayrı kart (Nabız glassTile içinde). Kart düzeni AI Limit Tracker'ın kartından uyarlandı
// (c) 2026 Bahadır Nuroğlu, MIT (mac/THIRD_PARTY.md): solda logo + ad + plan + hesap etiketi + tempo rozeti, sağda iki 270° halka.
import SwiftUI
import NabizCore

extension AIProviderID {
    var logo: BrandLogo {
        switch self {
        case .claude: .claude
        case .codex: .openai
        case .cursor: .cursor
        }
    }
}

struct AITab: View {
    var store = AIStore.shared

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.cards) { account in AIProviderCard(account: account, store: store) }
            HStack {
                if let t = store.dataUpdated {
                    Text("Güncellendi: \(Text(t, style: .time))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                MiniPill(title: store.isRefreshing ? "Yenileniyor…" : "Yenile", symbol: "arrow.clockwise", enabled: !store.isRefreshing) {
                    store.refresh(manual: true)
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

/// Seviyeye göre halka renkleri: normal mavi, yüksek / tempodan hızlı mor, kritik turuncu-kırmızı.
private extension AILimit {
    var gaugeColors: [Color] {
        switch level() {
        case 2: [Color(red: 0.98, green: 0.45, blue: 0.20), Color(red: 0.93, green: 0.22, blue: 0.38)]
        case 1: [Color(red: 0.24, green: 0.22, blue: 0.75), Color(red: 0.62, green: 0.45, blue: 0.98)]
        default: [Color(red: 0.29, green: 0.50, blue: 0.94), Color(red: 0.29, green: 0.50, blue: 0.94)]
        }
    }
}

private enum AICountdown {
    /// 24 saat içindeyse saat ("açılış 15:20"), değilse "3 g sonra açılır".
    static func opens(_ date: Date) -> String {
        date.timeIntervalSinceNow < 86_400
            ? "açılış " + date.formatted(date: .omitted, time: .shortened)
            : "\(AIText.short(date.timeIntervalSinceNow)) sonra açılır"
    }
}

private struct AIProviderCard: View {
    let account: AIAccount
    var store: AIStore
    @State private var expanded = false

    private static let notice = Color(red: 0.62, green: 0.45, blue: 0.98)

    var body: some View {
        let id = account.provider
        let u = store.usage(of: account)
        let front = AIFront.limits(u.limits, history: store.history)
        let multi = store.accounts(for: id).count > 1
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center, spacing: 9) {
                        BrandLogoShape(logo: id.logo).fill(Color.primary).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(id.name).font(.system(size: 15, weight: .bold))
                            if let sub = subtitle(u) { Text(sub).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                            if multi {
                                Text(store.label(account))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .lineLimit(1).fixedSize()
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .padding(.top, 3)
                            }
                        }
                    }
                    if let chip = chip(u) { chipView(chip).opacity(u.isStale() ? 0.45 : 1) }
                }
                Spacer(minLength: 4)
                if !front.isEmpty {
                    HStack(spacing: 8) { ForEach(front) { AIRingGauge(limit: $0) } }
                        .opacity(u.isStale() ? 0.45 : 1)
                } else if u.issue == nil {
                    emptyState(u)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let issue = u.issue { hint(issue) }
            if expanded && !u.limits.isEmpty {
                VStack(spacing: 8) { ForEach(u.limits) { AIMiniLimitRow(limit: $0) } }.padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: Radius.group)
        .contentShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .onTapGesture { if !u.limits.isEmpty { withAnimation(Motion.spring) { expanded.toggle() } } }
        .help(u.limits.isEmpty ? "" : (expanded ? "Gizle" : "Tüm limitler"))
    }

    /// Plan (büyük harf); eski veride "· 12 dk önce".
    private func subtitle(_ u: AIProviderUsage) -> String? {
        var parts: [String] = []
        if let plan = u.plan { parts.append(plan.uppercased()) }
        if u.isStale(), let at = u.updatedAt { parts.append("\(AIText.countdown(Date().timeIntervalSince(at))) önce") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private struct Chip { let text: String; let color: Color }

    /// Doldu (kırmızı) > "Bu hızla X'te tükenir" (mor; %90+ kırmızı) > not.
    private func chip(_ u: AIProviderUsage) -> Chip? {
        if let full = u.limits.filter({ $0.percent() >= 100 }).min(by: { ($0.resetsAt ?? .distantFuture) < ($1.resetsAt ?? .distantFuture) }) {
            return Chip(text: "Doldu" + (full.resetsAt.map { " · \(AICountdown.opens($0))" } ?? ""), color: Palette.critical)
        }
        guard let (limit, eta) = u.limits.compactMap({ l in l.timeToFull().map { (l, $0) } }).min(by: { $0.1 < $1.1 }) else {
            return u.note.map { Chip(text: $0, color: Color.primary) }
        }
        return Chip(text: "Bu hızla \(AIText.within(eta)) tükenir", color: limit.percent() >= 90 ? Palette.critical : Self.notice)
    }

    private func chipView(_ chip: Chip) -> some View {
        Text(chip.text)
            .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(chip.color)
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(chip.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    @ViewBuilder
    private func emptyState(_ u: AIProviderUsage) -> some View {
        if case .ok = u.state {
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "checkmark.circle").font(.system(size: 18))
                Text("Henüz kullanılmadı").font(.system(size: 12, weight: .semibold))
                Text("Tüm limitler boş").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.trailing)
        } else {
            Text("Yükleniyor…").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Sebep cümlesi + tek düzeltme düğmesi.
    private func hint(_ issue: AIIssue) -> some View {
        HStack(spacing: 7) {
            Circle().fill(issue.action == nil ? Color.secondary : Palette.warning).frame(width: 7, height: 7)
            Text(issue.text).font(.system(size: 10, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let title = issue.actionTitle, let action = issue.action {
                MiniPill(title: title) { store.perform(action, for: account) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

/// 270° halka: ortada yüzde, altında limit adı ve sıfırlanmaya kalan süre.
private struct AIRingGauge: View {
    let limit: AILimit
    private let size: CGFloat = 46
    private let line: CGFloat = 6

    var body: some View {
        let p = limit.percent()
        let fraction = min(max(p / 100, 0), 1)
        VStack(spacing: 1) {
            ZStack {
                Group {
                    Circle().trim(from: 0, to: 0.75).stroke(Palette.track, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    Circle().trim(from: 0, to: 0.75 * max(fraction, 0.012))
                        .stroke(LinearGradient(colors: limit.gaugeColors, startPoint: .bottomLeading, endPoint: .topTrailing),
                                style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: fraction)
                }
                .rotationEffect(.degrees(135))   // sol alttan başlar, saat yönünde dolar
                .padding(line / 2)
                Text("\(Int(p.rounded()))%")
                    .font(.system(size: p.rounded() >= 100 ? 10.5 : 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: size - line * 2 - 4)
                    .contentTransition(.numericText())
            }
            .frame(width: size, height: size)
            Text(limit.short ?? limit.label).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            // İkinci satır her halkada dolu: yan yana halkalar aynı hizada kalsın
            Text(limit.didReset() ? "yenilendi" : limit.resetsAt.map { AIText.countdown($0.timeIntervalSinceNow) } ?? limit.caption ?? " ")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 62)
    }
}

/// Açılan listedeki tek limit: ad + yüzde, ince çubuk, sıfırlanma süresi.
private struct AIMiniLimitRow: View {
    let limit: AILimit

    var body: some View {
        let p = limit.percent()
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(limit.label).font(.caption.weight(.medium)).lineLimit(1)
                Spacer()
                Text("%\(Int(p.rounded()))").font(.caption.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                Capsule().fill(Palette.track)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: limit.gaugeColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(1, max(0, p / 100))))
                    }
            }
            .frame(height: 5)
            if limit.didReset() {
                Text("Yenilendi, yeni veri bekleniyor").font(.caption2).foregroundStyle(.secondary)
            } else if let reset = limit.resetsAt {
                Text("\(AIText.countdown(reset.timeIntervalSinceNow)) sonra sıfırlanır").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
