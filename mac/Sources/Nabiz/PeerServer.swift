// Ag kabugu: NWListener (TCP, Bonjour _nabiz._tcp), TCP_NODELAY, 1 aktif + 1 aday baglanti (ConnectionSlots).
// Protokol mantigi PhoneModel/PeerSession'da.
import Foundation
import Network
import NabizCore

@MainActor
final class PeerServer {
    static let serviceType = "_nabiz._tcp"
    /// Sabit tercih edilen port (docs/protokol.md); doluysa sistem portu.
    static let preferredPort: UInt16 = 47821

    var onOpen: ((Int) -> Void)?
    var onData: ((Int, Data) -> Void)?
    /// (id, aktif miydi)
    var onClose: ((Int, Bool) -> Void)?
    /// nil = dinliyor; aksi halde hata metni.
    var onListenState: ((String?) -> Void)?

    private var listener: NWListener?
    private var conns: [Int: NWConnection] = [:]
    private(set) var slots = ConnectionSlots()
    private var nextId = 1
    private var txt: (name: String, deviceId: String)?
    private var stopped = true
    private var usedFallbackPort = false

    func start(name: String, deviceId: String) {
        txt = (name, deviceId)
        stopped = false
        startListener()
    }

    func stop() {
        stopped = true
        listener?.cancel(); listener = nil
        closeAll()
    }

    /// Dinlenen TCP portu (Bonjour / UDP kesif yaniti icin); dinlemiyorsa nil.
    var tcpPort: UInt16? { listener?.port?.rawValue }

    private static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true            // Nagle kapali: kucuk cerceveler gecikmeden gider
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        return NWParameters(tls: nil, tcp: tcp)
    }

    private func startListener() {
        guard !stopped, listener == nil, let txt else { return }
        do {
            let l: NWListener
            if !usedFallbackPort, let port = NWEndpoint.Port(rawValue: Self.preferredPort) {
                do { l = try NWListener(using: Self.parameters(), on: port) }
                catch { usedFallbackPort = true; l = try NWListener(using: Self.parameters()) }
            } else {
                l = try NWListener(using: Self.parameters())
            }
            var record = NWTXTRecord()
            record["ad"] = txt.name
            record["surum"] = "1"
            record["id"] = txt.deviceId
            l.service = NWListener.Service(name: txt.name, type: Self.serviceType, txtRecord: record)
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerState(state, from: l) }
            }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            listener = l
            l.start(queue: .main)
        } catch {
            onListenState?(error.localizedDescription)
            scheduleRestart()
        }
    }

    private func listenerState(_ state: NWListener.State, from l: NWListener) {
        guard l === listener else { return }
        switch state {
        case .ready: onListenState?(nil)
        case .failed(let e):
            onListenState?(e.localizedDescription)
            l.cancel(); listener = nil
            if !usedFallbackPort { usedFallbackPort = true; startListener(); return }   // sabit port dolu: sistem portu
            scheduleRestart()
        default: break
        }
    }

    private func scheduleRestart() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.startListener()
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = nextId; nextId += 1
        // Aday yeri doluysa hemen kapat (beklemede birakma): start + cancel.
        guard slots.opened(id) == .aday else {
            conn.start(queue: .main)
            conn.cancel()
            return
        }
        conns[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed, .cancelled: self?.connectionEnded(id)
                default: break
                }
            }
        }
        conn.start(queue: .main)
        onOpen?(id)
        receiveLoop(id: id, conn: conn)
    }

    private func receiveLoop(id: Int, conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.conns[id] != nil else { return }
                if let data, !data.isEmpty { self.onData?(id, data) }
                guard self.conns[id] != nil else { return }   // onData oturumu kapatmis olabilir
                if isComplete || error != nil { self.connectionEnded(id); return }
                self.receiveLoop(id: id, conn: conn)
            }
        }
    }

    private func connectionEnded(_ id: Int) {
        guard let conn = conns.removeValue(forKey: id) else { return }
        conn.cancel()
        let wasActive = slots.closed(id)
        onClose?(id, wasActive)
    }

    /// Aday dogrulandi: aktif olur, eski aktif baglanti sessizce kapatilir (onClose cagrilmaz).
    func promote(_ id: Int) -> (promoted: Bool, replaced: Int?) {
        let r = slots.promote(id)
        if let old = r.replaced, let conn = conns.removeValue(forKey: old) { conn.cancel() }
        return r
    }

    func send(_ data: Data, to id: Int) {
        conns[id]?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Baglanan tarafin adresi (Aktar veri baglantisini ayni cihaza baglamak icin); bilinmiyorsa nil.
    func remoteHost(of id: Int) -> String? { conns[id].flatMap { aktarHost(of: $0.endpoint) } }

    func close(_ id: Int) { connectionEnded(id) }

    func closeAll() { for id in Array(conns.keys) { connectionEnded(id) } }
}
