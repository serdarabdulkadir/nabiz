// Aktar modeli: kontrol mesajlari (aktar.*), 47823 dinleyici, aktarim kayitlari ve ayarlar.
// Veri tasima AktarEngine'dedir (ozel kuyruk); burada yalniz ana is parcacigindaki durum tutulur.
// Protokol: docs/protokol.md bolum 13.
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NabizCore

extension SettingsKey {
    static let aktarOn = "aktar.on"               // Aktar'i ac, varsayilan acik
    static let aktarAuto = "aktar.autoAccept"     // eslesmis telefondan otomatik kabul, varsayilan KAPALI
    static let aktarFolder = "aktar.folder"       // kayit konumu (yol); yoksa ~/Downloads/Nabız
}

enum AktarYon: Sendable { case gelen, giden }

enum AktarDurum: Equatable {
    case onayBekliyor        // gelen: kullanici karari bekleniyor
    case yanitBekleniyor     // giden: telefon henuz yanitlamadi
    case baglaniyor          // kabul edildi, veri baglantisi bekleniyor
    case suruyor
    case kesildi             // baglanti koptu, 10 dk icinde surebilir
    case bitti
    case hata(String)

    var etkin: Bool {
        switch self {
        case .bitti, .hata: false
        default: true
        }
    }
}

struct AktarKayit: Identifiable {
    let id: String   // aid
    let yon: AktarYon
    var cihaz: String
    var dosyalar: [AktarDosya]
    var toplam: Int64
    var bayt: Int64 = 0
    var hiz: Double = 0   // bayt/sn
    var durum: AktarDurum
    var baslangic = Date()
    /// Gelen: kaydedilen dosyalar; giden: kaynak dosyalar (Finder'da goster).
    var konumlar: [URL] = []
    var kaynaklar: [Int: URL] = [:]

    var baslik: String { dosyalar.count == 1 ? dosyalar[0].ad : "\(dosyalar.count) dosya" }
    var oran: Double { toplam > 0 ? min(1, Double(bayt) / Double(toplam)) : (durum == .bitti ? 1 : 0) }
}

@MainActor @Observable
final class AktarModel {
    static let shared = AktarModel()

    private(set) var enabled = true
    private(set) var records: [AktarKayit] = []
    /// Kullaniciya kisa uyari (panelde birkac sn gorunur).
    private(set) var notice: String?

    @ObservationIgnored private var listener: AktarListener?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var conns: [String: AktarConnection] = [:]
    @ObservationIgnored private var tokens: [String: UUID] = [:]
    @ObservationIgnored private var completed: [String: [Int: URL]] = [:]
    @ObservationIgnored private var expiry: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastProgress: [String: (bytes: Int64, at: Date)] = [:]
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    static let maxRecords = 20
    static let offerTimeout: TimeInterval = 120
    static let resumeWindow: TimeInterval = 600

    // MARK: Ayarlar

    static var autoAccept: Bool { UserDefaults.standard.bool(forKey: SettingsKey.aktarAuto) }

    static var defaultFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Nabız", isDirectory: true)
    }

    static var folder: URL {
        if let p = UserDefaults.standard.string(forKey: SettingsKey.aktarFolder), !p.isEmpty {
            return URL(fileURLWithPath: p, isDirectory: true)
        }
        return defaultFolder
    }

    // MARK: Yasam dongusu

    func start() {
        guard !started else { return }
        started = true
        refreshEnabled()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AktarModel.shared.refreshEnabled() }
        }
    }

    private func refreshEnabled() {
        let on = UserDefaults.standard.object(forKey: SettingsKey.aktarOn) as? Bool ?? true
        guard on != enabled || (on && listener == nil) else { return }
        enabled = on
        if on {
            let l = AktarListener { aid, host, conn in AktarModel.shared.authorize(aid: aid, host: host, conn: conn) }
            listener = l
            l.start()
        } else {
            listener?.stop(); listener = nil
            for r in records where r.durum.etkin { abort(r.id, notifyPeer: true, reason: "Aktar kapatıldı") }
        }
    }

    // MARK: Veri baglantisi yetkisi

    private func authorize(aid: String, host: String?, conn: AktarConnection) -> AktarJob? {
        guard enabled, let i = index(aid), let km = PhoneModel.shared.aktarKeyMaterial else { return nil }
        let r = records[i]
        switch r.durum {
        case .baglaniyor, .suruyor, .kesildi: break
        default: return nil
        }
        guard Self.sameDevice(host, PhoneModel.shared.aktarPeerHost) else { return nil }
        if let old = conns[aid] { old.cancel(deleteParts: false) }
        conns[aid] = conn
        let token = UUID()
        tokens[aid] = token
        expiry[aid]?.cancel(); expiry[aid] = nil
        lastProgress[aid] = nil
        records[i].durum = .suruyor
        return AktarJob(
            aid: aid, role: r.yon == .giden ? .gonderen : .alici, keyMaterial: km, files: r.dosyalar,
            sources: r.kaynaklar, destination: Self.folder, completed: completed[aid] ?? [:],
            onEvent: { ev in Task { @MainActor in AktarModel.shared.engineEvent(aid: aid, token: token, ev) } })
    }

    /// Ayni cihaz mi: ayni adres ailesinde adresler esit olmali. Bilinmiyorsa ya da aile farkliysa
    /// karsilastirilamaz; sifreleme (oturum anahtari) zaten yetkisiz baglantiyi reddeder.
    private static func sameDevice(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return true }
        if a.contains(":") != b.contains(":") { return true }
        return a == b
    }

    // MARK: Motor olaylari

    private func engineEvent(aid: String, token: UUID, _ ev: AktarEngineEvent) {
        guard tokens[aid] == token, let i = index(aid) else { return }
        switch ev {
        case .progress(let bytes):
            let now = Date()
            if let last = lastProgress[aid] {
                let dt = now.timeIntervalSince(last.at)
                if dt > 0.05 {
                    let inst = Double(max(0, bytes - last.bytes)) / dt
                    records[i].hiz = records[i].hiz == 0 ? inst : records[i].hiz * 0.6 + inst * 0.4
                    lastProgress[aid] = (bytes, now)
                }
            } else {
                lastProgress[aid] = (bytes, now)
            }
            records[i].bayt = bytes
            if records[i].durum != .suruyor, records[i].durum.etkin { records[i].durum = .suruyor }
        case .fileDone(let fid, let url):
            completed[aid, default: [:]][fid] = url
            records[i].konumlar.append(url)
        case .allDone(let failed):
            guard records[i].yon == .gelen else { return }
            PhoneModel.shared.sendAktar(.aktarBitti(AktarBitti(aid: aid, sonuc: failed.isEmpty ? .tamam : .hata,
                                                               hatali: failed.isEmpty ? nil : failed)))
            records[i].hiz = 0
            if failed.isEmpty {
                records[i].bayt = records[i].toplam
                records[i].durum = .bitti
                AlertCenter.shared.aktarInfo(title: "Aktar: alındı", body: "\(records[i].baslik) · \(Self.folder.lastPathComponent) klasörüne kaydedildi")
            } else {
                records[i].durum = .hata("\(failed.count) dosya doğrulanamadı")
            }
            finishConnection(aid, close: false)   // kapatmayi gonderen yapar (motor 10 sn sonra yine kapatir)
        case .closed(let c):
            conns[aid] = nil; tokens[aid] = nil
            guard records[i].durum.etkin else { return }
            records[i].hiz = 0
            switch c {
            case .normal, .dropped:
                records[i].durum = .kesildi
                scheduleExpiry(aid, after: Self.resumeWindow) { $0.expireResume(aid) }
            case .failed(let msg):
                abort(aid, notifyPeer: true, reason: msg)
            }
        }
    }

    // MARK: Karsidan gelen kontrol mesajlari

    func offerReceived(_ t: AktarTeklif) {
        guard index(t.aid) == nil else { return }
        let peer = PhoneModel.shared.phoneName ?? PhoneModel.shared.paired?.name ?? "Telefon"
        func refuse(_ n: AktarNeden) { PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: t.aid, kabul: false, neden: n))) }
        guard t.gecerli else { refuse(.reddedildi); return }
        guard enabled else { refuse(.kapali); return }
        guard Self.hasSpace(t.gercekToplam, in: Self.folder) else { refuse(.yerYok); return }
        records.insert(AktarKayit(id: t.aid, yon: .gelen, cihaz: peer, dosyalar: t.dosyalar, toplam: t.gercekToplam,
                                  durum: .onayBekliyor), at: 0)
        trim()
        if Self.autoAccept {
            respond(t.aid, accept: true)
        } else {
            AlertCenter.shared.aktarOffer(aid: t.aid, body: "\(peer) \(Self.describe(t.dosyalar)) göndermek istiyor")
            scheduleExpiry(t.aid, after: Self.offerTimeout) { $0.expireOffer(t.aid) }
        }
    }

    func replyReceived(_ y: AktarYanit) {
        guard let i = index(y.aid), records[i].yon == .giden, records[i].durum == .yanitBekleniyor else { return }
        if y.kabul {
            records[i].durum = .baglaniyor
            scheduleExpiry(y.aid, after: Self.offerTimeout) { $0.expireResume(y.aid) }
        } else {
            expiry[y.aid]?.cancel(); expiry[y.aid] = nil
            let why: String = switch y.neden {
            case .yerYok: "Telefonda yer yok"
            case .kapali: "Telefonda Aktar kapalı"
            default: "Telefon reddetti"
            }
            records[i].durum = .hata(why)
        }
    }

    func cancelReceived(_ c: AktarIptal) {
        guard let i = index(c.aid), records[i].durum.etkin else { return }
        if records[i].durum == .onayBekliyor {
            AlertCenter.shared.aktarRemoveOffer(aid: c.aid)
            expiry[c.aid]?.cancel(); expiry[c.aid] = nil
            records.remove(at: i)
        } else {
            abort(c.aid, notifyPeer: false, reason: "Telefon iptal etti")
        }
    }

    func doneReceived(_ b: AktarBitti) {
        guard let i = index(b.aid), records[i].yon == .giden, records[i].durum.etkin else { return }
        records[i].hiz = 0
        if b.sonuc == .tamam {
            records[i].bayt = records[i].toplam
            records[i].durum = .bitti
        } else {
            records[i].durum = .hata("\(b.hatali?.count ?? 1) dosya aktarılamadı")
        }
        finishConnection(b.aid)
    }

    /// Kontrol oturumu bitti: yanit / baglanti bekleyen kayitlar iptal; suren veri baglantilari kendi akisini bitirir.
    func sessionEnded() {
        for r in records where r.durum.etkin {
            switch r.durum {
            case .onayBekliyor:
                AlertCenter.shared.aktarRemoveOffer(aid: r.id)
                expiry[r.id]?.cancel(); expiry[r.id] = nil
                records.removeAll { $0.id == r.id }
            case .yanitBekleniyor, .baglaniyor, .kesildi:
                abort(r.id, notifyPeer: false, reason: "Telefon bağlantısı koptu")
            default: break
            }
        }
    }

    // MARK: Kullanici eylemleri

    /// Gelen teklifi kabul et / reddet (bildirim eylemi ya da panel dugmesi).
    func respond(_ aid: String, accept: Bool) {
        guard let i = index(aid), records[i].yon == .gelen, records[i].durum == .onayBekliyor else { return }
        expiry[aid]?.cancel(); expiry[aid] = nil
        AlertCenter.shared.aktarRemoveOffer(aid: aid)
        guard accept else {
            PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: aid, kabul: false, neden: .reddedildi)))
            records.remove(at: i)
            return
        }
        guard enabled else {
            PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: aid, kabul: false, neden: .kapali)))
            records.remove(at: i)
            return
        }
        guard Self.hasSpace(records[i].toplam, in: Self.folder) else {
            PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: aid, kabul: false, neden: .yerYok)))
            records.remove(at: i)
            showNotice("Diskte yer yok")
            return
        }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        records[i].durum = .baglaniyor
        records[i].baslangic = Date()
        PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: aid, kabul: true, port: Self.extraPort(listener))))
        scheduleExpiry(aid, after: Self.offerTimeout) { $0.expireResume(aid) }
    }

    /// Kullanici aktarimi iptal eder.
    func cancel(_ aid: String) {
        guard let i = index(aid), records[i].durum.etkin else { return }
        if records[i].durum == .onayBekliyor { respond(aid, accept: false); return }
        abort(aid, notifyPeer: true, reason: "İptal edildi")
    }

    func remove(_ aid: String) {
        guard let i = index(aid), !records[i].durum.etkin else { return }
        records.remove(at: i)
    }

    /// Dosyalari gonder (surukle-birak ya da Dosya sec). Klasorler atlanir.
    func send(_ urls: [URL]) {
        guard enabled else { showNotice("Aktar kapalı. Ayarlar > Telefon bölümünden aç."); return }
        guard PhoneModel.shared.isConnected else { showNotice("Telefon bağlı değil"); return }
        var files: [AktarDosya] = []
        var sources: [Int: URL] = [:]
        var skipped = 0
        for url in urls {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .contentTypeKey])
            guard v?.isDirectory != true, let size = v?.fileSize, files.count < AktarTeklif.enFazlaDosya else { skipped += 1; continue }
            let fid = files.count
            let mime = v?.contentType?.preferredMIMEType ?? UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? AktarDosya.bilinmeyenTur
            files.append(AktarDosya(fid: fid, ad: url.lastPathComponent, boyut: Int64(size), tur: mime,
                                    degisme: v?.contentModificationDate.map { Int64($0.timeIntervalSince1970) }))
            sources[fid] = url
        }
        guard !files.isEmpty else { showNotice("Klasörler gönderilemez, dosya seç"); return }
        if skipped > 0 { showNotice("\(skipped) klasör atlandı") }
        let aid = UUID().uuidString.lowercased()
        let total = files.reduce(Int64(0)) { $0 + $1.boyut }
        let peer = PhoneModel.shared.phoneName ?? PhoneModel.shared.paired?.name ?? "Telefon"
        var r = AktarKayit(id: aid, yon: .giden, cihaz: peer, dosyalar: files, toplam: total, durum: .yanitBekleniyor)
        r.kaynaklar = sources
        r.konumlar = files.compactMap { sources[$0.fid] }
        records.insert(r, at: 0)
        trim()
        PhoneModel.shared.sendAktar(.aktarTeklif(AktarTeklif(aid: aid, dosyalar: files, toplam: total,
                                                           port: Self.extraPort(listener))))
        scheduleExpiry(aid, after: Self.offerTimeout) { $0.expireOffer(aid) }
    }

    func pickFiles() {
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        p.prompt = "Gönder"
        NSApp.activate(ignoringOtherApps: true)
        p.begin { resp in
            guard resp == .OK else { return }
            let urls = p.urls
            Task { @MainActor in AktarModel.shared.send(urls) }
        }
    }

    func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Seç"
        p.directoryURL = Self.folder.deletingLastPathComponent()
        p.begin { resp in
            guard resp == .OK, let u = p.url else { return }
            UserDefaults.standard.set(u.path, forKey: SettingsKey.aktarFolder)
        }
    }

    func reveal(_ r: AktarKayit) {
        let existing = r.konumlar.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.isEmpty { NSWorkspace.shared.open(Self.folder) }
        else { NSWorkspace.shared.activateFileViewerSelecting(existing) }
    }

    // MARK: Ic

    private func index(_ aid: String) -> Int? { records.firstIndex { $0.id == aid } }

    private func finishConnection(_ aid: String, close: Bool = true) {
        expiry[aid]?.cancel(); expiry[aid] = nil
        completed[aid] = nil
        lastProgress[aid] = nil
        if close { conns[aid]?.finish() }
    }

    /// Aktarimi sonlandirir (hata / iptal): baglanti kapanir, yarim dosyalar silinir, istenirse karsiya `aktar.iptal` gider.
    private func abort(_ aid: String, notifyPeer: Bool, reason: String) {
        expiry[aid]?.cancel(); expiry[aid] = nil
        if let i = index(aid) {
            let r = records[i]
            records[i].durum = .hata(reason)
            records[i].hiz = 0
            if r.yon == .gelen { removeParts(r) }
        }
        if let c = conns[aid] { c.cancel(deleteParts: true) }
        conns[aid] = nil; tokens[aid] = nil
        completed[aid] = nil; lastProgress[aid] = nil
        if notifyPeer { PhoneModel.shared.sendAktar(.aktarIptal(AktarIptal(aid: aid))) }
    }

    private func removeParts(_ r: AktarKayit) {
        let fm = FileManager.default
        let done = completed[r.id] ?? [:]
        for f in r.dosyalar where done[f.fid] == nil {
            try? fm.removeItem(at: Self.folder.appendingPathComponent(AktarAd.partAdi(aid: r.id, fid: f.fid, ad: f.ad)))
        }
    }

    private func scheduleExpiry(_ aid: String, after seconds: TimeInterval, _ action: @escaping @MainActor (AktarModel) -> Void) {
        expiry[aid]?.cancel()
        expiry[aid] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    /// Teklif suresi doldu: gelen teklif sessizce kalkar; giden icin karsiya iptal gider.
    private func expireOffer(_ aid: String) {
        guard let i = index(aid) else { return }
        switch records[i].durum {
        case .onayBekliyor:
            AlertCenter.shared.aktarRemoveOffer(aid: aid)
            PhoneModel.shared.sendAktar(.aktarYanit(AktarYanit(aid: aid, kabul: false, neden: .reddedildi)))
            records.remove(at: i)
        case .yanitBekleniyor:
            abort(aid, notifyPeer: true, reason: "Yanıt gelmedi")
        default: break
        }
    }

    /// Veri baglantisi gelmedi / koptu ve pencere doldu.
    private func expireResume(_ aid: String) {
        guard let i = index(aid), records[i].durum == .baglaniyor || records[i].durum == .kesildi else { return }
        abort(aid, notifyPeer: true, reason: "Bağlantı kurulamadı")
    }

    private func trim() {
        var finished = 0
        records.removeAll { r in
            guard !r.durum.etkin else { return false }
            finished += 1
            return finished > Self.maxRecords
        }
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// Sabit port (47823) kullanilamiyorsa gercek port teklif / yanita eklenir.
    private static func extraPort(_ l: AktarListener?) -> Int? {
        guard let p = l?.port, p != AktarListener.preferredPort else { return nil }
        return Int(p)
    }

    // MARK: Yardimcilar

    /// "3 fotoğraf", "2 video", "4 dosya" ya da tek dosyanin adi.
    static func describe(_ files: [AktarDosya]) -> String {
        if files.count == 1 { return files[0].ad }
        if files.allSatisfy({ $0.tur.hasPrefix("image/") }) { return "\(files.count) fotoğraf" }
        if files.allSatisfy({ $0.tur.hasPrefix("video/") }) { return "\(files.count) video" }
        return "\(files.count) dosya"
    }

    /// Klasor (yoksa en yakin ust klasor) diskinde `needed` bayt yer var mi; okunamazsa engel yok.
    static func hasSpace(_ needed: Int64, in folder: URL) -> Bool {
        var url = folder
        let fm = FileManager.default
        while !fm.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
        let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return AktarYer.yeterli(gereken: needed, bos: free)
    }
}
