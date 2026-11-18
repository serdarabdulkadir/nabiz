// Ayarlar: ustte hap sekmeler (Moduller | Menu cubugu | Telefon | Genel), icerikte satir kutulari.
import SwiftUI
import ServiceManagement
import NabizCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case modules = "Modüller", bar = "Menü Çubuğu", notifications = "Bildirimler", phone = "Telefon", general = "Genel"
    var id: String { rawValue }
}

/// Sekme secimi: hap arac cubugunda (AppKit), icerik SwiftUI'de; ikisi bu nesneyi paylasir.
@MainActor @Observable
final class SettingsNav {
    static let shared = SettingsNav()
    var tab: SettingsTab = .modules
    /// Gecis yonu (true: sagdan gelir). tab degismeden once ayarlanir ki cikan gorunum da ters yone gitsin.
    var forward = true

    func select(_ new: SettingsTab) {
        guard new != tab else { return }
        let all = SettingsTab.allCases
        forward = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: tab) ?? 0)
        DispatchQueue.main.async { withAnimation(Motion.spring) { self.tab = new } }
    }
}

struct SettingsView: View {
    private var nav = SettingsNav.shared
    private var tab: SettingsTab { nav.tab }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch tab {
                    case .modules: ModulesSettings()
                    case .bar: BarSettings()
                    case .notifications: NotificationSettings()
                    case .phone: PhoneSettings()
                    case .general: GeneralSettings()
                    }
                }
                .id(tab)
                .transition(.directional(forward: nav.forward))
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
        }
        .frame(width: 560, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusEffectDisabled()
    }


}

// MARK: Ortak parcalar

private struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 15, weight: .semibold)).padding(.top, 4) }
}

private struct Footnote: View {
    let text: String
    var body: some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

/// Koyu yuvarlatilmis kap; satirlar arasina Divider koyulur.
private struct Box<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct Row<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

/// AppStorage anahtari disaridan verilen anahtar satiri.
private struct ToggleRow: View {
    var symbol: String? = nil
    let title: String
    var subtitle: String? = nil
    @AppStorage private var on: Bool

    init(symbol: String? = nil, title: String, subtitle: String? = nil, key: String, defaultOn: Bool) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        _on = AppStorage(wrappedValue: defaultOn, key)
    }

    var body: some View {
        Row(symbol: symbol, title: title, subtitle: subtitle) {
            Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: Moduller

private struct ModulesSettings: View {
    private var prefs = BarPrefs()

    var body: some View {
        let count = BarModule.allCases.filter { prefs.isOn($0) }.count
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Modüller")
            Box {
                ForEach(Array(BarModule.allCases.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { RowDivider() }
                    ToggleRow(symbol: m.symbol, title: m.title, subtitle: m.detail, key: m.key, defaultOn: m.defaultOn)
                }
            }
            SectionTitle(text: "Panel bölümleri")
            Box {
                ForEach(Array(PanelModule.allCases.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { RowDivider() }
                    ToggleRow(symbol: m.symbol, title: m.title, subtitle: m.detail, key: m.key, defaultOn: true)
                }
            }
            if count > 4 {
                Text("En çok 4 modül önerilir; fazlası menü çubuğunda sığmayabilir.")
                    .font(.caption).foregroundStyle(Color.orange)
            } else {
                Footnote(text: "Seçtiğin modüller menü çubuğunda gösterilir. En çok 4 modül önerilir.")
            }
        }
    }
}

// MARK: Menu cubugu

private struct BarSettings: View {
    @AppStorage(MenuBarKey.style) private var style: MenuBarStyle = .metin
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Stil")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MenuBarStyle.allCases) { s in
                    StyleCard(style: s, selected: style == s) { style = s }
                }
            }
            .padding(12)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            Footnote(text: "Önizlemeler şu anki değerlerle çizilir. Hangi değerlerin görüneceğini Modüller sekmesinden seçebilirsin.")
            Box {
                ToggleRow(title: "Yüzdeyi göster",
                          subtitle: "Halkalar, çubuklar, grafik ve tek simge stillerinde değeri simgenin yanında gösterir.",
                          key: MenuBarKey.showPercent, defaultOn: true)
                RowDivider()
                ToggleRow(title: "Kritik değerde kırmızı",
                          subtitle: "Pil %20 ve altı (şarjda değilken), disk %90 ve üstü, bellek basıncı kritik ya da CPU %85 ve üstü.",
                          key: MenuBarKey.critical, defaultOn: true)
            }
        }
    }
}

private struct StyleCard: View {
    let style: MenuBarStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                strip
                HStack(spacing: 6) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(style.title).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.primary)
                }
                Text(style.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Palette.fillSubtle, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Palette.stroke, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// Gercek menu cubugunu taklit eden koyu serit: Wi-Fi, stil onizlemesi, saat.
    private var strip: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.85))
            // Cok modul acikken onizleme karta sigmazsa orantili kuculur (tasma yok).
            ViewThatFits(in: .horizontal) {
                LiveBarArt(style: style).fixedSize()
                LiveBarArt(style: style).fixedSize().scaleEffect(0.8).frame(height: 20)
                LiveBarArt(style: style).fixedSize().scaleEffect(0.65).frame(height: 18)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .clipped()
            Text("12:41").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: Bildirimler

private extension AlertRuleID {
    var symbol: String {
        switch self {
        case .pilDusuk: "battery.25percent"
        case .pilDoldu: "battery.100percent.bolt"
        case .diskDolu: "internaldrive"
        case .cpuYuksek: "cpu"
        case .bellekKritik: "memorychip"
        case .sicak: "thermometer.high"
        case .baglantiKoptu: "wifi.slash"
        }
    }
    var unit: String { self == .sicak ? "°C" : (self == .baglantiKoptu ? " dk" : "%") }
    func detail(esik: Int, sure: Int) -> String {
        switch self {
        case .pilDusuk: "%\(esik) ve altında, şarjda değilken."
        case .pilDoldu: "Şarjdayken %\(esik) ve üstünde."
        case .diskDolu: "Doluluk %\(esik) ve üstünde."
        case .cpuYuksek: "%\(esik) ve üstü, \(sure) dakika kesintisiz."
        case .bellekKritik: "Bellek baskısı kritik olunca."
        case .sicak: "Pil sıcaklığı \(esik)°C ve üstünde."
        case .baglantiKoptu: "\(esik) dakikadır görülmediğinde."
        }
    }
}

private struct AlertRuleRows: View {
    let rule: AlertRuleID
    let subject: AlertSubject
    @AppStorage private var on: Bool
    @AppStorage private var esik: Int
    @AppStorage private var sure: Int

    init(rule: AlertRuleID, subject: AlertSubject) {
        self.rule = rule; self.subject = subject
        let p = AlertKey(rule, subject).prefix
        _on = AppStorage(wrappedValue: rule.varsayilanAcik(subject), "\(p).on")
        _esik = AppStorage(wrappedValue: rule.esikVarsayilan, "\(p).esik")
        _sure = AppStorage(wrappedValue: rule.sureVarsayilan, "\(p).sureDk")
    }

    var body: some View {
        Row(symbol: rule.symbol, title: rule.ad, subtitle: rule.detail(esik: esik, sure: sure)) {
            Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch)
        }
        if on, let range = rule.esikAraligi {
            Row(title: rule == .baglantiKoptu ? "Süre" : "Eşik") {
                Stepper(value: $esik, in: range) { Text("\(esik)\(rule.unit)").monospacedDigit() }
            }
            .padding(.leading, 36)
        }
        if on, let range = rule.sureAraligi {
            Row(title: "Süre") {
                Stepper(value: $sure, in: range) { Text("\(sure) dk").monospacedDigit() }
            }
            .padding(.leading, 36)
        }
    }
}

private struct NotificationSettings: View {
    var center = AlertCenter.shared

    private var permission: (text: String, ok: Bool) {
        switch center.authorization {
        case .authorized, .provisional, .ephemeral: ("İzin verildi", true)
        case .denied: ("İzin verilmedi", false)
        default: ("Henüz sorulmadı", false)
        }
    }

    private func group(_ subject: AlertSubject) -> some View {
        let rules = AlertRuleID.allCases.filter { $0.uygulanir(subject) }
        return Box {
            ForEach(Array(rules.enumerated()), id: \.element.rawValue) { i, r in
                if i > 0 { RowDivider() }
                AlertRuleRows(rule: r, subject: subject)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Bildirimler")
            Box {
                Row(symbol: "bell", title: "Bildirimlere izin ver", subtitle: permission.text) {
                    if center.authorization != .authorized {
                        Button("Sistem Ayarları") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                    }
                    if center.authorization == .notDetermined {
                        Button("İzin iste") { center.requestAuthorization() }
                    }
                }
            }
            SectionTitle(text: "Bu Mac")
            group(.mac)
            SectionTitle(text: "Telefon")
            group(.telefon)
            Box {
                Row(symbol: "paperplane", title: "Deneme bildirimi gönder") {
                    Button("Gönder") { center.sendTest() }
                }
            }
            Footnote(text: "Bir uyarı koşul doğru olunca bir kez bildirilir; en erken 30 dakika sonra yeniden. Telefon kuralları yalnız bağlıyken ve veri tazeyken çalışır.")
        }
        .task { await center.refreshAuthorization(requestIfNeeded: false) }
    }
}

// MARK: Telefon

private struct PhoneSettings: View {
    var phone = PhoneModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Eşleşme")
            Box {
                if let p = phone.paired {
                    Row(symbol: "smartphone", title: "Eşleşmiş telefon") { Text(p.name).foregroundStyle(.secondary) }
                    if let m = p.model ?? phone.phoneModel {
                        RowDivider()
                        Row(title: "Model") { Text(m).foregroundStyle(.secondary) }
                    }
                    RowDivider()
                    Row(title: "Durum") { Text(phone.isConnected ? "Bağlı" : "Bağlı değil").foregroundStyle(.secondary) }
                    RowDivider()
                    Row(title: "Eşleşmeyi unut", subtitle: "Telefonun anahtarı silinir; yeniden eşleşmen gerekir.") {
                        Button("Unut", role: .destructive) { phone.forget() }
                    }
                } else {
                    Row(symbol: "smartphone", title: "Eşleşmiş telefon yok",
                        subtitle: "Telefonda Nabız uygulamasını aç, aynı Wi-Fi ağında olduğundan emin ol.") { EmptyView() }
                }
            }
            SectionTitle(text: "Uzak bağlantı")
            RemoteAccessBox()
            SectionTitle(text: "Telefondan komutlar")
            Box {
                ToggleRow(symbol: "arrow.clockwise", title: "Yenile", subtitle: "Telefon anlık ölçüm isteyebilir.",
                          key: SettingsKey.cmdRefresh, defaultOn: true)
                RowDivider()
                ToggleRow(symbol: "lock", title: "Ekranı kilitle", subtitle: "Telefon Mac'in ekranını kilitleyebilir.",
                          key: SettingsKey.cmdLock, defaultOn: false)
                RowDivider()
                ToggleRow(symbol: "moon", title: "Uyut", subtitle: "Telefon Mac'i uyutabilir.",
                          key: SettingsKey.cmdSleep, defaultOn: false)
                RowDivider()
                ToggleRow(symbol: "sun.max", title: "Ekranı uyandır", subtitle: "Telefon kapalı ekranı açabilir. Kilidi açmaz.",
                          key: SettingsKey.cmdWake, defaultOn: true)
            }
            Footnote(text: "Kapalı komutlar telefona \"kapalı\" yanıtı döner.")
        }
    }
}

private struct RemoteAccessBox: View {
    @State private var info = NetworkAddresses.Info()
    @State private var copied = false

    var body: some View {
        Box {
            if let ts = info.tailscaleIP {
                let addr = "\(ts):\(PeerServer.preferredPort)"
                Row(symbol: "network", title: "Tailscale adresi", subtitle: "Telefonda \"Uzak adres\" alanına yaz.") {
                    HStack(spacing: 8) {
                        Text(addr).foregroundStyle(.secondary).textSelection(.enabled).monospacedDigit()
                        Button(copied ? "Kopyalandı" : "Kopyala") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(addr, forType: .string)
                            copied = true
                        }
                    }
                }
            } else {
                Row(symbol: "network", title: "Evin dışından görmek için",
                    subtitle: "Tailscale'i Mac'e ve telefona kur, aynı hesapla giriş yap.") {
                    Link("tailscale.com", destination: URL(string: "https://tailscale.com/download")!)
                }
            }
            if let ip = info.localIP {
                RowDivider()
                Row(symbol: "wifi", title: "Yerel adres") {
                    Text("\(ip):\(PeerServer.preferredPort)").foregroundStyle(.secondary).textSelection(.enabled).monospacedDigit()
                }
            }
        }
        .task { info = await NetworkAddresses.load() }
    }
}

// MARK: Genel

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.refresh) private var refresh = 2.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Genel")
            Box {
                Row(symbol: "power", title: "Girişte başlat", subtitle: "Mac açıldığında Nabız kendiliğinden başlar.") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                Row(symbol: "timer", title: "Yenileme hızı", subtitle: "Panel açıkken ölçüm aralığı.") {
                    Picker("", selection: $refresh) {
                        Text("1 sn").tag(1.0)
                        Text("2 sn").tag(2.0)
                        Text("5 sn").tag(5.0)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                RowDivider()
                Row(symbol: "info.circle", title: "Sürüm") { Text(version).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(Color.red) }
            Footnote(text: "Panel kapalıyken menü çubuğu 5 saniyede bir güncellenir.")
        }
        .onChange(of: launchAtLogin) { _, on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                error = nil
            } catch {
                self.error = error.localizedDescription
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
        .onChange(of: refresh) { _, _ in MonitorModel.shared.restart() }
    }
}


/// Arac cubugundaki sekme hapi (trafik isiklariyla ayni satirda, tiklanabilir).
struct SettingsTabPill: View {
    private var nav = SettingsNav.shared
    var body: some View {
        SlidingPillPicker(options: SettingsTab.allCases, selection: nav.tab, title: \.rawValue,
                          fontSize: 13, horizontalPadding: 11, verticalPadding: 5, fill: false) { nav.select($0) }
        .fixedSize()
        .preferredColorScheme(.dark)
    }
}
