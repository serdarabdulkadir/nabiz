import Foundation

enum SettingsKey {
    static let refresh = "refreshSeconds"
    static let cmdRefresh = "cmd.refresh"   // varsayilan acik
    static let cmdLock = "cmd.lock"         // varsayilan kapali
    static let cmdWake = "cmd.wake"         // varsayilan acik
    static let cmdSleep = "cmd.sleep"       // varsayilan kapali
}

/// Panel bolumleri (Mac'e ozel ek olcumler); hepsi varsayilan acik.
enum PanelModule: String, CaseIterable, Identifiable {
    case history, processes, sensors, devices
    var id: String { rawValue }
    var key: String { "panel.\(rawValue)" }
    var title: String {
        switch self {
        case .history: "Son 10 dk grafiği"
        case .processes: "Süreçler"
        case .sensors: "Sıcaklık ve fan"
        case .devices: "Bluetooth cihazları"
        }
    }
    var detail: String {
        switch self {
        case .history: "CPU, bellek ve ağın son 10 dakikası."
        case .processes: "En çok CPU kullanan 5 süreç; yalnız panel açıkken ölçülür."
        case .sensors: "CPU sıcaklığı ve (varsa) fan hızı."
        case .devices: "Bağlı klavye, fare ve kulaklıkların pil yüzdesi."
        }
    }
    var symbol: String {
        switch self {
        case .history: "chart.xyaxis.line"
        case .processes: "list.number"
        case .sensors: "thermometer.medium"
        case .devices: "headphones"
        }
    }
    var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

enum BarModule: String, CaseIterable, Identifiable {
    case cpu, ram, disk, battery, network, gpu, phone
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
        }
    }
    var defaultOn: Bool { self == .cpu || self == .ram }
}

enum MenuBarKey {
    static let style = "menubar.style"
    static let showPercent = "menubar.showPercent"   // varsayilan acik
    static let critical = "menubar.critical"         // varsayilan acik
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
        }
    }
}
