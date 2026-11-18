// Panel > Telefon sekmesi: bos durum, SAS onayi, bagli telefon karolari (CPU yok).
import SwiftUI
import NabizCore

struct PhoneTab: View {
    var phone: PhoneModel

    var body: some View {
        switch phone.link {
        case .bagli: PhoneStats(phone: phone)
        case .sasBekliyor: SASCard(phone: phone)
        case .dinliyor, .elSikisma: PhoneEmpty(phone: phone)
        }
    }
}

private struct PhoneEmpty: View {
    var phone: PhoneModel

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "smartphone").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Telefonda Nabız uygulamasını aç, aynı Wi-Fi").font(.headline).multilineTextAlignment(.center)
            if let p = phone.paired {
                Text("Eşleşmiş telefon: \(p.name)").font(.caption).foregroundStyle(.secondary)
            }
            Text(status).font(.caption).foregroundStyle(statusIsError ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 12)
        .glassTile(cornerRadius: Radius.group)
    }

    private var statusIsError: Bool { phone.listenError != nil || phone.lastError != nil }

    private var status: String {
        if let e = phone.listenError { return "Dinleme başlatılamadı: \(e)" }
        if let e = phone.lastError { return e }
        return phone.link == .elSikisma ? "Telefon bağlanıyor…" : "Dinleniyor"
    }
}

private struct SASCard: View {
    var phone: PhoneModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Eşleşme kodu").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(phone.sas ?? "------")
                .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                .kerning(4)
                .textSelection(.enabled)
            Text("Telefondaki kodla aynıysa onayla.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button { phone.confirmSAS(accepted: false) } label: { pill("Reddet") }
                Button { phone.confirmSAS(accepted: true) } label: { pill("Onayla", strong: true) }
            }
            .buttonStyle(PressableStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 12)
        .glassTile(cornerRadius: Radius.group)
    }

    private func pill(_ text: String, strong: Bool = false) -> some View {
        Text(text).font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(strong ? Palette.selection : Color.clear, in: Capsule())
            .glassCapsule(interactive: true)
    }
}

private struct PhoneStats: View {
    var phone: PhoneModel

    var body: some View {
        let s = phone.snapshot
        VStack(spacing: 8) {
            HStack {
                Text(([phone.phoneName, phone.phoneModel].compactMap { $0 }
                      + (phone.latencyMs.map { ["\($0) ms"] } ?? [])).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if let seen = phone.lastSeen {
                    Text("Son görülme: \(Text(seen, style: .time))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 6)
            GlassGroup {
                VStack(spacing: 8) {
                    HStack(spacing: 8) { batteryTile(s); memTile(s) }
                    HStack(spacing: 8) { diskTile(s); netTile(s) }
                }
            }
            VStack(spacing: 6) {
                StatRow(label: "Termal durum", value: thermalText(s?.thermal), critical: s?.thermal == "critical")
                if let b = s?.battery, b.health != nil || b.cycles != nil {
                    StatRow(label: "Pil sağlığı / döngü", value: "\(Format.percent(b.health)) · \(b.cycles.map(String.init) ?? Format.missing)")
                }
            }
            .padding(12)
            .glassTile(cornerRadius: Radius.group)
            PhoneExtras(phone: phone)
        }
    }

    private func batteryTile(_ s: Snapshot?) -> some View {
        let b = s?.battery
        var detail: [String] = []
        if let b, b.charging { detail.append("Şarj oluyor") }
        if let t = b?.temp { detail.append(String(format: "%.1f°C", t)) }
        return RingTile(title: "Pil", fraction: b.map { Double($0.level) / 100 }, value: Format.percent(b?.level),
                        detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                        critical: b.map { $0.level <= 20 && !$0.charging } ?? false, bolt: b?.charging ?? false)
    }

    private func memTile(_ s: Snapshot?) -> some View {
        let frac = s?.mem.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        return RingTile(title: "Bellek", fraction: frac, value: Format.percent(fraction: frac),
                        detail: s?.mem.map { "\(Format.bytes($0.used)) / \(Format.bytes($0.total))" },
                        critical: s?.mem?.pressure == "critical",
                        warning: (frac ?? 0) >= Thresholds.warning)
    }

    private func diskTile(_ s: Snapshot?) -> some View {
        let frac = s?.disk.map { $0.total > 0 ? Double($0.used) / Double($0.total) : 0 }
        return RingTile(title: "Depolama", fraction: frac, value: Format.percent(fraction: frac),
                        detail: s?.disk.map { "\(Format.bytes($0.total - $0.used, base: 1000)) boş" },
                        critical: (frac ?? 0) >= 0.9, warning: (frac ?? 0) >= Thresholds.warning)
    }

    private func netTile(_ s: Snapshot?) -> some View {
        VStack(spacing: 6) {
            TileTitle(text: "Ağ")
            VStack(spacing: 4) {
                Text("↓ \(Format.speed(s?.net?.down))")
                Text("↑ \(Format.speed(s?.net?.up))")
            }
            .roundedDigits(size: 13)
            .frame(height: 54)
            Text(" ").font(.caption2)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .glassTile()
    }

    private func thermalText(_ t: String?) -> String {
        switch t {
        case "normal": "Normal"
        case "warn": "Yüksek"
        case "critical": "Kritik"
        default: Format.missing
        }
    }
}

// MARK: Bildirimler ve aramalar (yalniz ilgili telefon izni aciksa)

private struct PhoneExtras: View {
    var phone: PhoneModel

    var body: some View {
        let perm = phone.perm
        let notifs = PanelModule.phoneNotifs.isOn
        let calls = PanelModule.phoneCalls.isOn
        let showNotifs = notifs && perm.bildirimler
        let showCalls = calls && (perm.aramaGecmisi || perm.cagriYonetimi)
        if showNotifs { NotificationsTile(phone: phone) }
        if showCalls { CallsTile(phone: phone) }
        if (notifs || calls) && !perm.anyOn {
            Text("Bildirim ve aramalar için telefonda Ayarlar > Mac ile paylaş")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).padding(.horizontal, 6)
        }
    }
}

private struct NotificationsTile: View {
    var phone: PhoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TileTitle(text: "Bildirimler")
                Spacer()
                MiniPill(title: "Tümü") { PhoneWindow.show(.bildirimler) }
            }
            if phone.notifications.isEmpty {
                Text("Bildirim yok").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(phone.notifications.prefix(3)) { n in NotificationLine(phone: phone, n: n) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: Radius.group)
    }
}

private struct NotificationLine: View {
    var phone: PhoneModel
    let n: PhoneNotification
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            NotifIcon(phone: phone, paket: n.paket, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(PhoneFormat.notifTitle(n)).font(.caption.weight(.medium)).lineLimit(1)
                if let m = n.metin, !m.isEmpty {
                    Text(m).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if hover && n.kapatilabilir {
                Button { phone.dismiss(n.anahtar) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 18, height: 18).background(Palette.fill, in: Circle()).contentShape(Circle())
                }
                .buttonStyle(PressableStyle()).accessibilityLabel("Kapat")
            } else {
                PhoneFormat.when(n.zaman).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(minHeight: 22)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct CallsTile: View {
    var phone: PhoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TileTitle(text: "Aramalar")
                Spacer()
                if phone.perm.cagriYonetimi {
                    MiniPill(title: "Ara", symbol: "phone") { PhoneWindow.show(.aramalar, keypad: true) }
                }
            }
            if !phone.perm.aramaGecmisi {
                Text("Arama geçmişi kapalı").font(.caption).foregroundStyle(.secondary)
            } else {
                let recent = Array((phone.callLog ?? []).sorted { $0.zaman > $1.zaman }.prefix(3))
                if recent.isEmpty {
                    Text(phone.callLog == nil ? "Yükleniyor…" : "Arama kaydı yok").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(recent.enumerated()), id: \.element.stableId) { _, e in CallLine(phone: phone, e: e) }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(cornerRadius: Radius.group)
    }
}

private struct CallLine: View {
    var phone: PhoneModel
    let e: CallLogEntry

    var body: some View {
        let missed = e.yon == .cevapsiz
        Button { phone.dial(e.numara) } label: {
            HStack(spacing: 8) {
                Image(systemName: PhoneFormat.callSymbol(e.yon)).font(.system(size: 10))
                    .foregroundStyle(missed ? Palette.critical : Color.secondary).frame(width: 20)
                Text(PhoneFormat.callName(e, phone)).font(.caption.weight(.medium)).lineLimit(1)
                    .foregroundStyle(missed ? Palette.critical : Color.primary)
                Spacer(minLength: 6)
                PhoneFormat.when(e.zaman).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(minHeight: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!phone.perm.cagriYonetimi)
        .help(phone.perm.cagriYonetimi ? "Geri ara" : "")
    }
}
