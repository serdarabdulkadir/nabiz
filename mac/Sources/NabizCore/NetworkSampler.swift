// Ag: getifaddrs toplam bayt sayaclari, iki ornek arasi fark.
import Foundation
import Darwin

public enum NetworkSampler {
    /// Sayac farki. Sayac geri giderse (tasma, arayuz kaybi) 0 doner; uydurma sicrama olmaz.
    public static func delta(previous: UInt64, current: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    /// B/s
    public static func rate(previous: UInt64, current: UInt64, seconds: Double) -> UInt64 {
        guard seconds > 0 else { return 0 }
        return UInt64(Double(delta(previous: previous, current: current)) / seconds)
    }

    /// (alinan, gonderilen) toplam bayt; lo0 haric, yalniz ayakta arayuzler.
    public static func readTotals() -> (rx: UInt64, tx: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let ifa = p.pointee
            cur = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = ifa.ifa_data else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            if String(cString: ifa.ifa_name) == "lo0" { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes)
            tx += UInt64(d.ifi_obytes)
        }
        return (rx, tx)
    }
}
