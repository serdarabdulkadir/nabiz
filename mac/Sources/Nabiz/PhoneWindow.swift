// Telefon penceresi: Bildirimler | Aramalar | Kisiler. Tek ornek pencere (SettingsWindow kalibi).
// Veri PhoneModel'den gelir ve yalniz bellektedir; diske yazilmaz.
import SwiftUI
import AppKit
import NabizCore

enum PhoneSection: String, CaseIterable, Identifiable {
    case bildirimler, aramalar, kisiler
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bildirimler: "Bildirimler"
        case .aramalar: "Aramalar"
        case .kisiler: "Kişiler"
        }
    }
    var symbol: String {
        switch self {
        case .bildirimler: "bell"
        case .aramalar: "phone"
        case .kisiler: "person.2"
        }
    }
}

@MainActor @Observable
final class PhoneWindowState {
    static let shared = PhoneWindowState()
    var section: PhoneSection = .bildirimler
    /// Tus takimi acilmasi istendi (Aramalar bolumu tuketir).
    var keypadPending = false
}

@MainActor
enum PhoneWindow {
    private static var window: NSWindow?

    static func show(_ section: PhoneSection = .bildirimler, keypad: Bool = false) {
        let state = PhoneWindowState.shared
        state.section = section
        state.keypadPending = keypad
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Nabız Telefon"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: PhoneWindowView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: Ortak parcalar

/// Panel ve pencerede kullanilan kucuk hap dugme.
struct MiniPill: View {
    let title: String
    var symbol: String? = nil
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.caption.weight(.medium))
            }
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Palette.fill, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

/// Bildirimin uygulama ikonu (yoksa zil simgesi), yuvarlatilmis kare.
struct NotifIcon: View {
    let phone: PhoneModel
    let paket: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let img = phone.icon(for: paket) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "bell.fill").font(.system(size: size * 0.5)).foregroundStyle(.secondary)
                    .frame(width: size, height: size).background(Palette.fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Fotograf varsa fotograf, yoksa bas harf avatari.
struct ContactAvatar: View {
    var record: ContactRecord?
    var name: String?
    var size: CGFloat = 32

    private static let cache = NSCache<NSString, NSImage>()

    private var photo: NSImage? {
        guard let record, let b64 = record.foto else { return nil }
        let key = "\(record.kid)|\(b64.count)" as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: b64), let img = NSImage(data: data) else { return nil }
        Self.cache.setObject(img, forKey: key)
        return img
    }

    var body: some View {
        Group {
            if let photo {
                Image(nsImage: photo).resizable().scaledToFill()
            } else if let c = ContactText.initial(record?.ad ?? name ?? "") {
                Text(c).font(.system(size: size * 0.42, weight: .semibold)).frame(width: size, height: size)
                    .background(Palette.fill)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
                    .frame(width: size, height: size).background(Palette.fill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

@MainActor
enum PhoneFormat {
    /// Bugun ise saat, degilse gun/ay saat.
    static func when(_ epoch: Int) -> Text {
        let d = Date(timeIntervalSince1970: TimeInterval(epoch))
        return Calendar.current.isDateInToday(d) ? Text(d, style: .time) : Text(d, format: .dateTime.day().month().hour().minute())
    }

    static func notifTitle(_ n: PhoneNotification) -> String {
        [n.uygulama, n.baslik].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func callName(_ e: CallLogEntry, _ phone: PhoneModel) -> String {
        phone.contact(for: e.numara)?.ad ?? e.kisiAdi ?? e.numara
    }

    static func callSymbol(_ y: CallLogDirection) -> String {
        y == .giden ? "phone.arrow.up.right" : "phone.arrow.down.left"
    }

    static func duration(_ s: Int) -> String { s >= 60 ? "\(s / 60) dk" : "\(s) sn" }
}

private struct PhoneNote: View {
    let text: String
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .fillBox(radius: Radius.card)
    }
}

/// Satirlari Divider ile ayrilmis yuvarlatilmis kap.
private struct PhoneBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        LazyVStack(spacing: 0) { content }
            .frame(maxWidth: .infinity)
            .fillBox(radius: Radius.card)
    }
}

private struct PaneTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(text).font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing
        }
    }
}

// MARK: Pencere

struct PhoneWindowView: View {
    private var state = PhoneWindowState.shared
    private var phone = PhoneModel.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                Group {
                    switch state.section {
                    case .bildirimler: NotificationsPane(phone: phone)
                    case .aramalar: CallsPane(phone: phone)
                    case .kisiler: ContactsPane(phone: phone)
                    }
                }
                .padding(.horizontal, 18).padding(.top, 38).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 660, minHeight: 440, idealHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .focusEffectDisabled()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PhoneSection.allCases) { s in
                let on = s == state.section
                Button { withAnimation(Motion.spring) { state.section = s } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.symbol).font(.system(size: 13)).frame(width: 20)
                        Text(s.title).font(.system(size: 13, weight: on ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if s == .bildirimler, !phone.notifications.isEmpty {
                            Text("\(phone.notifications.count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(on ? Palette.selection : Color.clear, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            Spacer()
            if !phone.isConnected {
                Text("Telefon bağlı değil").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
        }
        .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 14)
        .frame(width: 170)
    }
}

// MARK: Bildirimler

private struct NotificationsPane: View {
    let phone: PhoneModel
    @State private var replyingKey: String?
    @State private var replyText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: "Bildirimler") {
                if phone.perm.bildirimler, phone.notifications.contains(where: \.kapatilabilir) {
                    MiniPill(title: "Tümünü kapat", symbol: "xmark") { phone.clearAll() }
                }
            }
            if !phone.perm.bildirimler {
                PhoneNote(text: "Bildirimleri görmek için telefonda Ayarlar > Mac ile paylaş bölümünden Bildirimler'i aç.")
            } else if phone.notifications.isEmpty {
                PhoneNote(text: "Bildirim yok.")
            } else {
                PhoneBox {
                    ForEach(Array(phone.notifications.enumerated()), id: \.element.anahtar) { i, n in
                        if i > 0 { Divider().padding(.leading, 52) }
                        row(n)
                    }
                }
            }
        }
    }

    private func row(_ n: PhoneNotification) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                NotifIcon(phone: phone, paket: n.paket, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PhoneFormat.notifTitle(n)).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let m = n.metin, !m.isEmpty {
                        Text(m).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if n.yanitlanabilir && replyingKey != n.anahtar {
                        Button("Yanıtla") { replyText = ""; replyingKey = n.anahtar }
                            .buttonStyle(PressableStyle()).font(.caption.weight(.medium)).padding(.top, 2)
                    }
                    if let r = phone.replyResults[n.anahtar] {
                        Text(resultText(r)).font(.caption2).foregroundStyle(r == .tamam ? Color.secondary : Palette.warning)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    PhoneFormat.when(n.zaman).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    if n.kapatilabilir {
                        Button { phone.dismiss(n.anahtar) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .frame(width: 20, height: 20).background(Palette.fill, in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle()).help("Telefonda kapat").accessibilityLabel("Kapat")
                    }
                }
            }
            if replyingKey == n.anahtar {
                HStack(spacing: 8) {
                    TextField("Yanıt yaz", text: $replyText).textFieldStyle(.plain).font(.system(size: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6).glassCapsule()
                        .onSubmit { send(n) }
                    MiniPill(title: "Gönder", enabled: !replyText.trimmingCharacters(in: .whitespaces).isEmpty) { send(n) }
                    MiniPill(title: "Vazgeç") { replyingKey = nil }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func send(_ n: PhoneNotification) {
        phone.reply(n.anahtar, replyText)
        replyText = ""; replyingKey = nil
    }

    private func resultText(_ r: NotifResult) -> String {
        switch r {
        case .tamam: "Yanıt gönderildi"
        case .bulunamadi: "Bildirim telefonda artık yok"
        case .desteklenmiyor: "Bu bildirim yanıtı desteklemiyor"
        case .hata: "Yanıt gönderilemedi"
        }
    }
}

// MARK: Aramalar

private enum CallFilter: String, CaseIterable { case son = "Son", cevapsiz = "Cevapsız" }

private struct CallsPane: View {
    let phone: PhoneModel
    private var state = PhoneWindowState.shared
    @State private var filter: CallFilter = .son
    @State private var showKeypad = false

    init(phone: PhoneModel) { self.phone = phone }

    private var entries: [CallLogEntry] {
        let all = (phone.callLog ?? []).sorted { $0.zaman > $1.zaman }
        return filter == .cevapsiz ? all.filter { $0.yon == .cevapsiz } : all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: "Aramalar") {
                MiniPill(title: "Tuş takımı", symbol: "circle.grid.3x3.fill", enabled: phone.perm.cagriYonetimi) { showKeypad.toggle() }
                    .popover(isPresented: $showKeypad, arrowEdge: .bottom) { KeypadPopover(phone: phone, isPresented: $showKeypad) }
            }
            if !phone.perm.cagriYonetimi {
                PhoneNote(text: "Arama başlatmak için telefonda Ayarlar > Mac ile paylaş bölümünden Çağrı yönetimi'ni aç.")
            }
            if !phone.perm.aramaGecmisi {
                PhoneNote(text: "Son aramaları görmek için telefonda Ayarlar > Mac ile paylaş bölümünden Arama geçmişi'ni aç.")
            } else {
                SlidingPillPicker(options: CallFilter.allCases, selection: filter, title: \.rawValue,
                                  fontSize: 13, horizontalPadding: 14, verticalPadding: 5, fill: false) { filter = $0 }
                    .fixedSize()
                if entries.isEmpty {
                    PhoneNote(text: phone.callLog == nil ? "Arama geçmişi yükleniyor…" : "Arama kaydı yok.")
                } else {
                    PhoneBox {
                        ForEach(Array(entries.enumerated()), id: \.element.stableId) { i, e in
                            if i > 0 { Divider().padding(.leading, 52) }
                            row(e)
                        }
                    }
                }
            }
        }
        .onAppear { consumeKeypadRequest() }
        .onChange(of: state.keypadPending) { _, _ in consumeKeypadRequest() }
    }

    private func consumeKeypadRequest() {
        guard state.keypadPending else { return }
        state.keypadPending = false
        Task { try? await Task.sleep(for: .milliseconds(250)); showKeypad = phone.perm.cagriYonetimi }
    }

    private func row(_ e: CallLogEntry) -> some View {
        let missed = e.yon == .cevapsiz
        let contact = phone.contact(for: e.numara)
        return Button { phone.dial(e.numara) } label: {
            HStack(spacing: 10) {
                ContactAvatar(record: contact, name: e.kisiAdi ?? e.numara, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(PhoneFormat.callName(e, phone)).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(missed ? Palette.critical : Color.primary).lineLimit(1)
                    HStack(spacing: 4) {
                        Image(systemName: PhoneFormat.callSymbol(e.yon)).font(.system(size: 9))
                        Text(missed ? "Cevapsız" : "\(e.yon == .giden ? "Giden" : "Gelen"), \(PhoneFormat.duration(e.sureSn))")
                            .font(.caption)
                    }
                    .foregroundStyle(missed ? Palette.critical : Color.secondary)
                }
                Spacer(minLength: 8)
                PhoneFormat.when(e.zaman).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!phone.perm.cagriYonetimi)
        .help("Ara")
    }
}

private struct KeypadPopover: View {
    let phone: PhoneModel
    @Binding var isPresented: Bool
    @State private var number = ""

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

    private var suggestions: [ContactRecord] {
        guard phone.perm.kisiler, !number.isEmpty else { return [] }
        return Array(phone.contacts.search(number).prefix(3))
    }

    var body: some View {
        VStack(spacing: 10) {
            TextField("Numara", text: $number)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit()
                .onSubmit(place)
                .onChange(of: number) { _, v in
                    let f = ContactText.dialable(v)
                    if f != v { number = f }
                }
            if !suggestions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(suggestions) { c in
                        Button { if let n = c.numaralar.first { number = ContactText.dialable(n.no) } } label: {
                            HStack {
                                Text(c.ad).font(.caption.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(c.numaralar.first?.no ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .fillBox(radius: Radius.row)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button { number.append(key) } label: {
                            Text(key).font(.system(size: 19, weight: .medium, design: .rounded))
                                .frame(width: 52, height: 40)
                                .background(Palette.fill, in: Capsule(style: .continuous))
                                .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            HStack(spacing: 10) {
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left").foregroundStyle(.secondary).frame(width: 52, height: 36)
                }
                .buttonStyle(PressableStyle()).accessibilityLabel("Sil")
                Button(action: place) {
                    Label("Ara", systemImage: "phone.fill").font(.callout.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 106, height: 36)
                        .background(Palette.charging.opacity(number.isEmpty || !phone.perm.cagriYonetimi ? 0.35 : 1), in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(PressableStyle()).disabled(number.isEmpty || !phone.perm.cagriYonetimi)
            }
        }
        .padding(14)
        .frame(width: 210)
    }

    private func place() {
        guard !number.isEmpty, phone.perm.cagriYonetimi else { return }
        phone.dial(number)
        number = ""
        isPresented = false
    }
}

// MARK: Kisiler

private struct ContactsPane: View {
    let phone: PhoneModel
    @State private var query = ""

    private var list: [ContactRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? phone.contacts.all : phone.contacts.search(q)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(text: "Kişiler") {
                if let t = phone.contactsTotal, phone.perm.kisiler {
                    Text("\(t)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if !phone.perm.kisiler {
                PhoneNote(text: "Kişileri görmek için telefonda Ayarlar > Mac ile paylaş bölümünden Kişiler'i aç.")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                    TextField("İsim veya numara ara", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Aramayı temizle")
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassCapsule()
                if !phone.perm.cagriYonetimi {
                    PhoneNote(text: "Arama başlatmak için telefonda Çağrı yönetimi'ni aç.")
                }
                let items = list
                if items.isEmpty {
                    PhoneNote(text: phone.contactsLoading ? "Kişiler yükleniyor…" : (query.isEmpty ? "Kişi yok." : "Eşleşen kişi yok."))
                } else {
                    PhoneBox {
                        ForEach(Array(items.enumerated()), id: \.element.kid) { i, c in
                            if i > 0 { Divider().padding(.leading, 52) }
                            row(c)
                        }
                    }
                }
            }
        }
    }

    private func row(_ c: ContactRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ContactAvatar(record: c, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(c.ad).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if c.favori { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                ForEach(Array(c.numaralar.enumerated()), id: \.offset) { _, n in
                    Button { phone.dial(n.no) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "phone").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(n.no).font(.caption).monospacedDigit()
                            Text(typeTitle(n.tur)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!phone.perm.cagriYonetimi)
                    .help("Ara")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func typeTitle(_ tur: String) -> String {
        switch tur {
        case "cep": "Cep"
        case "ev": "Ev"
        case "is": "İş"
        default: "Diğer"
        }
    }
}
