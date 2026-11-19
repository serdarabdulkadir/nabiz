// UDP kesif yanitlayici (docs/protokol.md bolum 11): 47822/UDP dinler, {"t":"kesif","v":1} gelince
// gonderene unicast {"t":"kesif.yanit",...} doner. Port acilamazsa sessizce yalniz Bonjour kalir.
import Foundation
import Network
import NabizCore

@MainActor
final class DiscoveryResponder {
    private var listener: NWListener?
    private var flows: [ObjectIdentifier: NWConnection] = [:]
    private var info: (id: String, name: String, port: () -> UInt16?)?

    func start(deviceId: String, name: String, tcpPort: @escaping () -> UInt16?) {
        info = (deviceId, name, tcpPort)
        guard listener == nil, let port = NWEndpoint.Port(rawValue: PeerDiscovery.port),
              let l = try? NWListener(using: .udp, on: port) else { return }
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.handle(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.stop() } }   // sessizce vazgec
        }
        listener = l
        l.start(queue: .main)
    }

    func stop() {
        listener?.cancel(); listener = nil
        for c in flows.values { c.cancel() }
        flows = [:]
    }

    private func handle(_ conn: NWConnection) {
        let key = ObjectIdentifier(conn)
        flows[key] = conn
        conn.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { Task { @MainActor in self?.flows[key] = nil } }
        }
        conn.start(queue: .main)
        conn.receiveMessage { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self else { conn.cancel(); return }
                if let data, PeerDiscovery.isRequest(data), let info = self.info, let port = info.port(),
                   let reply = PeerDiscovery.reply(id: info.id, ad: info.name, port: port) {
                    conn.send(content: reply, completion: .contentProcessed { _ in conn.cancel() })
                } else {
                    conn.cancel()
                }
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            conn.cancel()   // yanit gelmeyen akis takili kalmasin
        }
    }
}
