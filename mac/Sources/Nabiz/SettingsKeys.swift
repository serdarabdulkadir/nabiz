import Foundation

enum SettingsKey {
    static let refresh = "refreshSeconds"
    static let cmdRefresh = "cmd.refresh"   // varsayilan acik
    static let cmdLock = "cmd.lock"         // varsayilan kapali
    static let cmdWake = "cmd.wake"         // varsayilan acik
    static let cmdSleep = "cmd.sleep"       // varsayilan kapali
    static let phoneNotifMac = "phone.notifMac"     // telefon bildirimini Mac'te goster, varsayilan acik
    static let phoneCallBubble = "phone.callBubble" // gelen aramada baloncuk, varsayilan acik
    static let aiEnabled = "ai.enabledProviders"    // acik AI saglayicilari (yoksa bu Mac'te bulunanlar)
    static let aiNotify75 = "ai.notify75"           // varsayilan acik
    static let aiNotify90 = "ai.notify90"           // varsayilan acik
    static let aiNotifyReset = "ai.notifyReset"     // varsayilan acik
    static let aiShowOnPhone = "ai.showOnPhone"     // AI limitlerini telefonda goster, varsayilan acik
}

/// Panel bolumleri (Mac'e ozel ek olcumler); hepsi varsayilan acik.
enum PanelModule: String, CaseIterable, Identifiable {
    case history, processes, sensors, devices, phoneNotifs, phoneCalls, ai
    var id: String { rawValue }
    var key: String { "panel.\(rawValue)" }
    var title: String {
        switch self {
        case .history: "Son 10 dk grafiği"
        case .processes: "Süreçler"
        case .sensors: "Sıcaklık ve fan"
        case .devices: "Bluetooth cihazları"
        case .phoneNotifs: "Telefon bildirimleri"
        case .phoneCalls: "Telefon aramaları"
        case .ai: "AI limitleri"
        }
    }
    var detail: String {
        switch self {
        case .history: "CPU, bellek ve ağın son 10 dakikası."
        case .processes: "En çok CPU kullanan 5 süreç; yalnız panel açıkken ölçülür."
        case .sensors: "CPU sıcaklığı ve (varsa) fan hızı."
        case .devices: "Bağlı klavye, fare ve kulaklıkların pil yüzdesi."
        case .phoneNotifs: "Telefon sekmesinde son bildirimler; telefonda izin açıksa."
        case .phoneCalls: "Telefon sekmesinde son aramalar ve Ara düğmesi; telefonda izin açıksa."
        case .ai: "Panelde AI sekmesi: Claude, Codex ve Cursor kullanım limitleri (en az bir sağlayıcı açıksa)."
        }
    }
    var symbol: String {
        switch self {
        case .history: "chart.xyaxis.line"
        case .processes: "list.number"
        case .sensors: "thermometer.medium"
        case .devices: "headphones"
        case .phoneNotifs: "bell"
        case .phoneCalls: "phone"
        case .ai: "gauge.with.dots.needle.50percent"
        }
    }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

enum BarModule: String, CaseIterable, Identifiable {
    case cpu, ram, disk, battery, network, gpu, phone, ai
    var id: String { rawValue }
    var key: String { "bar.\(rawValue)" }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .ram: "RAM"
        case .disk: "Disk"
        case .battery: "Pil"
        case .network: "Ağ"
        case .gpu: "GPU"
        case .phone: "Telefon pili"
        case .ai: "AI"
        }
    }
    var defaultOn: Bool { self == .cpu || self == .ram || self == .ai }
}

enum MenuBarKey {
    static let style = "menubar.style"
    static let showPercent = "menubar.showPercent"   // varsayilan acik
    static let critical = "menubar.critical"         // varsayilan acik
    static let aiStyle = "ai.barStyle"               // AIBarStyle, varsayilan column
}

/// Menu cubugu gorunumu. Ham deger @AppStorage "menubar.style" anahtarinda saklanir.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case metin, ikiSatir, halkalar, barlar, grafik, tekSimge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .metin: "Metin"
        case .ikiSatir: "İki satır"
        case .halkalar: "Halkalar"
        case .barlar: "Çubuklar"
        case .grafik: "Grafik"
        case .tekSimge: "Tek simge"
        }
    }
    var detail: String {
        switch self {
        case .metin: "Tek satırda kısa etiketler ve değerler. Örnek: C 29% · R 61%."
        case .ikiSatir: "Üstte küçük etiket, altta değer. Modüller yan yana dizilir."
        case .halkalar: "Her modül için ince bir halka; ortasında harfi durur."
        case .barlar: "Her modül için dikey ince bir çubuk ve harfi."
        case .grafik: "CPU'nun son örnekleri küçük bir grafikte, yanında değer."
        case .tekSimge: "Nabız simgesi ve en kritik modülün değeri."
        }
    }
}

extension BarModule {
    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .network: "arrow.up.arrow.down"
        case .gpu: "display"
        case .phone: "smartphone"
        case .ai: "gauge.with.dots.needle.50percent"
        }
    }
    var detail: String {
        switch self {
        case .cpu: "Toplam işlemci kullanımı."
        case .ram: "Kullanılan bellek; basınç kritikse kırmızı."
        case .disk: "Başlangıç diskinin doluluğu."
        case .battery: "Mac pili. Masaüstü Mac'te görünmez."
        case .network: "İndirme ve yükleme hızı."
        case .gpu: "Grafik işlemci kullanımı."
        case .phone: "Eşleşmiş telefonun pil yüzdesi."
        case .ai: "AI limitleri; stil ve seçilen hesap Menü Çubuğu sekmesinde. En az bir sağlayıcı bağlıysa görünür."
        }
    }
}
