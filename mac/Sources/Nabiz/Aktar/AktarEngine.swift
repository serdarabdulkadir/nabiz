// Aktar veri baglantisi (docs/protokol.md bolum 13): 47823 dinleyici + baglanti basina alma/gonderme motoru.
// Tum G/C ve sifreleme ozel bir seri kuyrukta yapilir (ana is parcacigi kilitlenmez); dosyalar akisla okunur / yazilir.
// Protokol mantigi NabizCore'dadir (AktarCrypto, AktarFraming, AktarMessage, AktarDosyaYazici, AktarDosyaOkuyucu).
import Foundation
import Network
import os
import NabizCore

/// Veri baglantisinin isi: aid kabul edilince AktarModel uretir.
struct AktarJob: Sendable {
    let aid: String
    let role: AktarRole
    let keyMaterial: Data
    let files: [AktarDosya]
    /// Gonderen: fid -> kaynak dosya (yalniz kullanicinin sectikleri).
    let sources: [Int: URL]
    /// Alici: kayit klasoru.
    let destination: URL
    /// Alici: onceki baglantida tamamlanmis dosyalar (yeniden indirilmez).
    let completed: [Int: URL]
    let onEvent: @Sendable (AktarEngineEvent) -> Void
}

enum AktarEngineEvent: Sendable {
    /// Toplam islenen bayt (devam eden ofsetler dahil).
    case progress(bytes: Int64)
    /// Alici: dosya dogrulandi ve hedefe tasindi.
    case fileDone(fid: Int, url: URL)
    /// Alici: tum dosyalar islendi; model kontrol kanalindan aktar.bitti yollar.
    case allDone(failed: [Int])
    case closed(AktarClosure)
}

enum AktarClosure: Sendable, Equatable {
    case normal
    case dropped
    case failed(String)
}

typealias AktarAuthorizer = @MainActor @Sendable (_ aid: String, _ host: String?, _ connection: AktarConnection) -> AktarJob?

/// IPv6 kapsam kimligi ve IPv4-eslemeli onek atilir; iki baglantinin ayni cihazdan geldigini karsilastirmak icin.
func aktarNormalizeHost(_ s: String) -> String {
    var h = s
    if let i = h.firstIndex(of: "%") { h = String(h[..<i]) }
    if h.lowercased().hasPrefix("::ffff:") { h.removeFirst(7) }
    return h.lowercased()
}

func aktarHost(of endpoint: NWEndpoint) -> String? {
    guard case .hostPort(let host, _) = endpoint else { return nil }
    return aktarNormalizeHost("\(host)")
}

// MARK: Dinleyici

final class AktarListener: @unchecked Sendable {
    static let preferredPort: UInt16 = 47823

    private let queue = DispatchQueue(label: "nabiz.aktar", qos: .userInitiated)
    private let authorizer: AktarAuthorizer
    private let portBox = OSAllocatedUnfairLock<UInt16?>(initialState: nil)
    // Asagidakiler yalniz `queue` uzerinde okunur / yazilir.
    private var listener: NWListener?
    private var running = false
    private var usedFallback = false

    /// Dinlenen port (hazir degilse nil); herhangi bir is parcacigindan okunabilir.
    var port: UInt16? { portBox.withLock { $0 } }

    init(authorizer: @escaping AktarAuthorizer) { self.authorizer = authorizer }

    func start() {
        queue.async {
            self.running = true
            self.usedFallback = false
            self.startListener()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.listener?.cancel()
            self.listener = nil
            self.portBox.withLock { $0 = nil }
        }
    }

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = false            // toplu yazim: Nagle acik kalir (docs/protokol.md bolum 13)
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        return NWParameters(tls: nil, tcp: tcp)
    }

    private func startListener() {
        guard running, listener == nil else { return }
        do {
            let l: NWListener
            if !usedFallback, let p = NWEndpoint.Port(rawValue: Self.preferredPort) {
                do { l = try NWListener(using: Self.parameters(), on: p) }
                catch { usedFallback = true; l = try NWListener(using: Self.parameters()) }
            } else {
                l = try NWListener(using: Self.parameters())
            }
            l.stateUpdateHandler = { [weak self] state in self?.listenerState(state, from: l) }
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener = l
            l.start(queue: queue)
        } catch {
            scheduleRestart()
        }
    }

    private func listenerState(_ state: NWListener.State, from l: NWListener) {
        guard l === listener else { return }
        switch state {
        case .ready:
            portBox.withLock { $0 = l.port?.rawValue }
        case .failed:
            l.cancel(); listener = nil
            portBox.withLock { $0 = nil }
            if !usedFallback { usedFallback = true; startListener(); return }   // sabit port dolu: sistem portu
            scheduleRestart()
        default: break
        }
    }

    private func scheduleRestart() {
        queue.asyncAfter(deadline: .now() + 5) { self.startListener() }
    }

    private func accept(_ conn: NWConnection) {
        guard running else { conn.cancel(); return }
        AktarConnection(conn: conn, queue: queue, authorizer: authorizer).start()
    }
}

// MARK: Baglanti

/// Tek veri baglantisi. Durumu yalniz kendi seri kuyrugunda degisir; disaridan yalniz `finish` / `cancel` cagrilir.
/// Baglanti bitene kadar kendi kendini tutar (kapaninca isleyicileri temizler).
final class AktarConnection: @unchecked Sendable {
    private static let chunk = 256 * 1024
    private static let maxInflight = 8
    private static let firstFrameTimeout: TimeInterval = 10
    private static let senderCloseGrace: TimeInterval = 10

    private enum Phase { case awaitingConnect, awaitingAuth, active, closed }

    private let conn: NWConnection
    private let queue: DispatchQueue
    private let authorizer: AktarAuthorizer

    private var phase = Phase.awaitingConnect
    private var buffer = PeerFrameBuffer()
    private var pending: [Data] = []
    private var receiving = false
    private var cipher: AktarCipher?
    private var job: AktarJob?
    private var timeout: DispatchWorkItem?
    private var perFid: [Int: UInt64] = [:]
    private var lastReport = DispatchTime.now()

    // Alici
    private var offsets: [Int: UInt64] = [:]
    private var writers: [Int: AktarDosyaYazici] = [:]
    private var done: Set<Int> = []
    private var failed: Set<Int> = []
    private var retried: Set<Int> = []
    private var allDoneReported = false

    // Gonderen
    private var started = false
    private var todo: [(fid: Int, ofset: UInt64)] = []
    private var current: (fid: Int, reader: AktarDosyaOkuyucu)?
    private var inflight = 0

    init(conn: NWConnection, queue: DispatchQueue, authorizer: @escaping AktarAuthorizer) {
        self.conn = conn; self.queue = queue; self.authorizer = authorizer
    }

    // MARK: Disaridan

    func start() {
        conn.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled: ended(.dropped)
            default: break
            }
        }
        conn.start(queue: queue)
        let t = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .awaitingConnect || self.phase == .awaitingAuth else { return }
            self.ended(.normal)
        }
        timeout = t
        queue.asyncAfter(deadline: .now() + Self.firstFrameTimeout, execute: t)
        receive()
    }

    /// Gonderen: alici `aktar.bitti` yolladi; baglanti kapatilir.
    func finish() { queue.async { self.ended(.normal) } }

    /// Iptal: baglanti kapanir. `deleteParts` ise acik yarim dosyalar da silinir.
    func cancel(deleteParts: Bool) {
        queue.async {
            if deleteParts { for (_, w) in self.writers { w.kapat(sil: true) }; self.writers = [:] }
            self.ended(.normal)
        }
    }

    // MARK: Alma dongusu

    private func receive() {
        guard phase != .closed, !receiving else { return }
        receiving = true
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, complete, error in
            receiving = false
            if let data, !data.isEmpty { ingest(data) }
            if phase == .closed { return }
            if complete || error != nil { ended(allDoneReported ? .normal : .dropped); return }
            if phase == .awaitingAuth { return }   // yetki gelince yeniden baslar
            receive()
        }
    }

    private func ingest(_ data: Data) {
        do { pending += try buffer.append(data) } catch { ended(.failed("Çerçeve hatası")); return }
        drain()
    }

    private func drain() {
        while phase != .closed, !pending.isEmpty {
            switch phase {
            case .awaitingConnect:
                let first = pending.removeFirst()
                guard let aid = AktarBaglan.decode(frame: first) else { ended(.normal); return }
                phase = .awaitingAuth
                requestAuthorization(aid)
                return
            case .awaitingAuth, .closed:
                return
            case .active:
                handle(pending.removeFirst())
            }
        }
    }

    private func requestAuthorization(_ aid: String) {
        let host = aktarHost(of: conn.endpoint)
        let auth = authorizer
        Task { @MainActor [self] in
            let job = auth(aid, host, self)
            queue.async { self.authorized(job) }
        }
    }

    private func authorized(_ job: AktarJob?) {
        guard phase == .awaitingAuth else { return }
        guard let job else { ended(.normal); return }
        timeout?.cancel()
        do {
            let keys = try AktarCrypto.deriveKeys(sessionKeyMaterial: job.keyMaterial, aid: job.aid)
            cipher = AktarCipher(role: job.role, keys: keys)
        } catch {
            ended(.failed("Anahtar türetilemedi")); return
        }
        self.job = job
        phase = .active
        if job.role == .alici { beginReceiver(job) }
        drain()
        receive()
    }

    // MARK: Gonderme yardimcilari

    private func send(_ plain: Data, completion: (@Sendable (Bool) -> Void)? = nil) throws {
        guard cipher != nil else { throw AktarYazmaHatasi.kapali }
        let packet = try cipher!.seal(plain)
        let framed = try PeerFrame.encode(packet)
        conn.send(content: framed, completion: .contentProcessed { error in completion?(error == nil) })
    }

    private func sendControl(_ k: AktarKontrol) {
        do { try send(AktarFraming.encodeControl(try AktarKontrolCodec.encode(k))) }
        catch { ended(.failed("Gönderilemedi")) }
    }

    private func report(force: Bool) {
        guard let job else { return }
        let now = DispatchTime.now()
        guard force || now.uptimeNanoseconds &- lastReport.uptimeNanoseconds > 200_000_000 else { return }
        lastReport = now
        var total: UInt64 = 0
        for f in job.files { total += min(perFid[f.fid] ?? 0, UInt64(max(0, f.boyut))) }
        job.onEvent(.progress(bytes: Int64(total)))
    }

    // MARK: Alici

    private func partURL(_ job: AktarJob, _ fid: Int) -> URL {
        job.destination.appendingPathComponent(AktarAd.partAdi(aid: job.aid, fid: fid, ad: job.files[fid].ad))
    }

    private func beginReceiver(_ job: AktarJob) {
        try? FileManager.default.createDirectory(at: job.destination, withIntermediateDirectories: true)
        let fm = FileManager.default
        offsets = AktarDevam.ofsetler(dosyalar: job.files) { fid in
            guard let n = (try? fm.attributesOfItem(atPath: self.partURL(job, fid).path))?[.size] as? NSNumber else { return nil }
            return n.uint64Value
        }
        for (fid, _) in job.completed where job.files.indices.contains(fid) {
            done.insert(fid)
            offsets[fid] = UInt64(max(0, job.files[fid].boyut))   // gonderen yalniz dosya.son yollar
        }
        for (fid, o) in offsets { perFid[fid] = o }
        report(force: true)
        sendControl(.devam(ofsetler: offsets))
        checkAllDone()
    }

    private func writer(_ job: AktarJob, _ fid: Int) throws -> AktarDosyaYazici {
        if let w = writers[fid] { return w }
        let f = job.files[fid]
        let w = try AktarDosyaYazici(partURL: partURL(job, fid), ad: f.ad, boyut: f.boyut, degisme: f.degisme,
                                     fid: fid, devamEt: offsets[fid] ?? 0)
        writers[fid] = w
        offsets[fid] = nil   // devam yalniz ilk acilista gecerli
        perFid[fid] = w.yazilan
        return w
    }

    private func receiveData(_ job: AktarJob, fid: Int, ofset: UInt64, bayt: Data) {
        guard job.files.indices.contains(fid) else { ended(.failed("Geçersiz dosya numarası")); return }
        if done.contains(fid) || failed.contains(fid) { return }
        do {
            let w = try writer(job, fid)
            try w.yaz(ofset: ofset, bayt: bayt)
            perFid[fid] = w.yazilan
            report(force: false)
        } catch {
            ended(.failed(Self.describe(error)))
        }
    }

    private func fileEnd(_ job: AktarJob, fid: Int, sha: String) {
        guard job.files.indices.contains(fid) else { return }
        if done.contains(fid) || failed.contains(fid) { checkAllDone(); return }
        do {
            let w = try writer(job, fid)
            switch try w.bitir(sha256: sha, hedefKlasor: job.destination) {
            case .tamam(let url):
                writers[fid] = nil
                done.insert(fid)
                perFid[fid] = UInt64(max(0, job.files[fid].boyut))
                job.onEvent(.fileDone(fid: fid, url: url))
            case .shaUyusmuyor, .eksik:
                w.kapat(sil: true)
                writers[fid] = nil
                perFid[fid] = 0
                // Bir kez yeniden iste; ikinci uyusmazlikta dosya hatali sayilir.
                if retried.insert(fid).inserted { sendControl(.dosyaHata(fid: fid)) } else { failed.insert(fid) }
            }
            report(force: true)
            checkAllDone()
        } catch {
            ended(.failed(Self.describe(error)))
        }
    }

    private func checkAllDone() {
        guard let job, !allDoneReported, done.count + failed.count == job.files.count else { return }
        allDoneReported = true
        job.onEvent(.allDone(failed: failed.sorted()))
        // Gonderen kapatmazsa biraz bekleyip biz kapatiriz.
        queue.asyncAfter(deadline: .now() + Self.senderCloseGrace) { self.ended(.normal) }
    }

    // MARK: Gonderen

    private func startSender(_ job: AktarJob, offsets o: [Int: UInt64]) {
        guard !started else { return }
        started = true
        todo = job.files.map { f in
            let x = o[f.fid] ?? 0
            return (fid: f.fid, ofset: x <= UInt64(max(0, f.boyut)) ? x : 0)
        }
        for t in todo { perFid[t.fid] = t.ofset }
        report(force: true)
        pump()
    }

    private func pump() {
        guard phase == .active, let job, job.role == .gonderen, started else { return }
        do {
            while inflight < Self.maxInflight {
                if current == nil {
                    guard !todo.isEmpty else { return }
                    let next = todo.removeFirst()
                    guard let url = job.sources[next.fid] else { throw AktarOkumaHatasi.acilamadi("Kaynak dosya yok") }
                    let r = try AktarDosyaOkuyucu(url: url, beklenenBoyut: job.files[next.fid].boyut)
                    try r.basla(ofset: next.ofset)
                    current = (next.fid, r)
                }
                guard let cur = current else { return }
                if let part = try cur.reader.sonraki(en: Self.chunk) {
                    let plain = try AktarFraming.encodeData(fid: cur.fid, ofset: part.ofset, bayt: part.bayt)
                    let fid = cur.fid
                    let n = UInt64(part.bayt.count)
                    inflight += 1
                    try send(plain) { [self] ok in
                        queue.async { [self] in
                            inflight -= 1
                            guard phase == .active else { return }
                            if ok {
                                perFid[fid, default: 0] += n
                                report(force: false)
                                pump()
                            } else {
                                ended(.dropped)
                            }
                        }
                    }
                } else {
                    let sha = cur.reader.sha256
                    cur.reader.kapat()
                    current = nil
                    sendControl(.dosyaSon(fid: cur.fid, sha256: sha))
                    if phase != .active { return }
                }
            }
        } catch {
            ended(.failed(Self.describe(error)))
        }
    }

    // MARK: Sifreli cerceve isleme

    private func handle(_ packet: Data) {
        guard let job else { return }
        let plain: Data
        do {
            guard let p = try cipher?.open(packet) else { ended(.failed("Şifre çözülemedi")); return }
            plain = p
        } catch {
            ended(.failed("Şifre doğrulanamadı")); return
        }
        let frame: AktarFrame
        do { frame = try AktarFraming.decode(plain) } catch { ended(.failed("Çerçeve çözülemedi")); return }
        switch frame {
        case .veri(let fid, let ofset, let bayt):
            if job.role == .alici { receiveData(job, fid: fid, ofset: ofset, bayt: bayt) }
        case .kontrol(let json):
            // Bilinmeyen / bozuk kontrol mesaji olumcul degil.
            guard let k = try? AktarKontrolCodec.decode(json) else { return }
            switch (job.role, k) {
            case (.alici, .dosyaSon(let fid, let sha)):
                fileEnd(job, fid: fid, sha: sha)
            case (.gonderen, .devam(let o)):
                startSender(job, offsets: o)
            case (.gonderen, .dosyaHata(let fid)):
                guard job.files.indices.contains(fid) else { return }
                todo.append((fid: fid, ofset: 0))
                perFid[fid] = 0
                report(force: true)
                pump()
            default:
                break
            }
        }
    }

    // MARK: Kapanis

    private func ended(_ closure: AktarClosure) {
        guard phase != .closed else { return }
        phase = .closed
        timeout?.cancel()
        for (_, w) in writers { w.kapat(sil: false) }
        writers = [:]
        current?.reader.kapat(); current = nil
        pending = []
        conn.stateUpdateHandler = nil
        conn.cancel()
        job?.onEvent(.closed(closure))
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case let e as AktarYazmaHatasi:
            switch e {
            case .ofsetUyusmuyor: return "Veri sırası bozuldu"
            case .tasma: return "Beklenenden fazla veri geldi"
            case .kapali: return "Dosya kapalı"
            case .io(let m): return "Dosya yazılamadı: \(m)"
            }
        case let e as AktarOkumaHatasi:
            switch e {
            case .degisti: return "Dosya gönderilirken değişti"
            case .acilamadi(let m): return "Dosya okunamadı: \(m)"
            case .ofsetGecersiz: return "Geçersiz konum"
            }
        default:
            return "Aktarım hatası"
        }
    }
}
