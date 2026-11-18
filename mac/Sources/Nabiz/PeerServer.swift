// Ag kabugu: NWListener (TCP, Bonjour _nabiz._tcp) + tek aktif baglanti. Protokol mantigi PhoneModel/PeerSession'da.
import Foundation
import Network

@MainActor
final class PeerServer {
    static let serviceType = "_nabiz._tcp"
    /// Sabit tercih edilen port (docs/protokol.md); doluysa sistem portu.
    static let preferredPort: UInt16 = 47821

    var onOpen: ((Int) -> Void)?
    var onData: ((Int, Data) -> Void)?
    var onClose: ((Int) -> Void)?
    /// nil = dinliyor; aksi halde hata metni.
    var onListenState: ((String?) -> Void)?

    private var listener: NWListener?
    private var active: (id: Int, conn: NWConnection)?
    private var nextId = 1
    private var lastReceive = Date()
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
        closeActive()
    }

    private func startListener() {
        guard !stopped, listener == nil, let txt else { return }
        do {
            let l: NWListener
            if !usedFallbackPort, let port = NWEndpoint.Port(rawValue: Self.preferredPort) {
                do { l = try NWListener(using: .tcp, on: port) }
                catch { usedFallbackPort = true; l = try NWListener(using: .tcp) }
            } else {
                l = try NWListener(using: .tcp)
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
        if let a = active {
            // Tek oturum: canli baglanti varken ikinci baglanti reddedilir; 20 sn sessiz kalmis (olu) baglanti yerine gecer.
            if Date().timeIntervalSince(lastReceive) < 20 { conn.cancel(); return }
            closeActive()
            _ = a
        }
        let id = nextId; nextId += 1
        active = (id, conn)
        lastReceive = Date()
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
                guard let self, self.active?.id == id else { return }
                if let data, !data.isEmpty {
                    self.lastReceive = Date()
                    self.onData?(id, data)
                }
                guard self.active?.id == id else { return }   // onData oturumu kapatmis olabilir
                if isComplete || error != nil { self.connectionEnded(id); return }
                self.receiveLoop(id: id, conn: conn)
            }
        }
    }

    private func connectionEnded(_ id: Int) {
        guard active?.id == id else { return }
        active?.conn.cancel()
        active = nil
        onClose?(id)
    }

    func send(_ data: Data) {
        active?.conn.send(content: data, completion: .contentProcessed { _ in })
    }

    func closeActive() {
        guard let a = active else { return }
        connectionEnded(a.id)
    }
}
