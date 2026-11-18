// Mac'in yerel IPv4 adresi ve (varsa) Tailscale IPv4 adresi. Ayarlar > Telefon > Uzak baglanti.
import Foundation

enum NetworkAddresses {
    struct Info: Sendable {
        var localIP: String?
        var tailscaleIP: String?
    }

    static func load() async -> Info {
        await Task.detached { Info(localIP: localIPv4(), tailscaleIP: tailscaleIPv4()) }.value
    }

    private static func localIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var best: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if best == nil || name == "en0" { best = ip }
            }
        }
        return best
    }

    private static func tailscaleIPv4() -> String? {
        let fm = FileManager.default
        let candidates = ["/Applications/Tailscale.app/Contents/MacOS/Tailscale", "/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale"]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["ip", "-4"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first.map(String.init)
            if p.terminationStatus == 0, let out, out.split(separator: ".").count == 4 { return out }
        }
        // CLI yoksa: Tailscale arayuzu (utun, 100.64.0.0/10) adresi.
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let o = ip.split(separator: ".").compactMap { Int($0) }
            if o.count == 4, o[0] == 100, (64...127).contains(o[1]) { return ip }
        }
        return nil
    }
}
