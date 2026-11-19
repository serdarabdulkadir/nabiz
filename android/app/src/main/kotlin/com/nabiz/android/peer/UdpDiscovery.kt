package com.nabiz.android.peer

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface

/** UDP kesif paketleri (docs/protokol.md bolum 11). Saf kodlama/cozum. */
object UdpCodec {
    const val PORT = 47822

    class Reply(val id: String, val name: String, val port: Int)

    fun request(): ByteArray = PeerJson.write(mapOf("t" to "kesif", "v" to 1)).toByteArray(Charsets.UTF_8)

    fun encodeReply(id: String, name: String, port: Int): ByteArray =
        PeerJson.write(mapOf("t" to "kesif.yanit", "v" to 1, "id" to id, "ad" to name, "port" to port)).toByteArray(Charsets.UTF_8)

    /** Gecersiz/bilinmeyen paket: null (yok sayilir). */
    fun parseReply(data: ByteArray, len: Int = data.size): Reply? {
      return try {
        val m = PeerJson.parse(String(data, 0, len, Charsets.UTF_8)) as? Map<*, *> ?: return null
        val f = Fields(m)
        if (f.strOpt("t") != "kesif.yanit" || f.longOpt("v") != 1L) return null
        val id = f.strOpt("id")?.takeIf { it.isNotBlank() } ?: return null
        val port = f.longOpt("port")?.takeIf { it in 1..65535 }?.toInt() ?: return null
        Reply(id, f.strOpt("ad")?.takeIf { it.isNotBlank() } ?: id, port)
      } catch (_: Exception) { null }
    }

    /** Yonlendirilmis yayin adresi: ip | ~maske. IPv4 (4 bayt) ve 0..32 onek uzunlugu. */
    fun broadcastOf(ip: ByteArray, prefix: Int): ByteArray {
        require(ip.size == 4 && prefix in 0..32)
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        val v = ((ip[0].toInt() and 255) shl 24) or ((ip[1].toInt() and 255) shl 16) or ((ip[2].toInt() and 255) shl 8) or (ip[3].toInt() and 255)
        val b = v or mask.inv()
        return byteArrayOf((b ushr 24).toByte(), (b ushr 16).toByte(), (b ushr 8).toByte(), b.toByte())
    }

    /** Arayuz adi hotspot'a benziyor mu (ap0, swlan0, wlan1...). */
    fun isHotspotName(name: String): Boolean = name.startsWith("ap") || name.startsWith("swlan") || name == "wlan1"
}

/** Ayakta IPv4 arayuzleri (ad, adres, onek). */
internal data class LocalNet(val ifName: String, val ip: ByteArray, val prefix: Int, val broadcast: InetAddress?)

internal fun localNets(): List<LocalNet> = try {
    NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }.flatMap { ni ->
        ni.interfaceAddresses.filter { it.address is Inet4Address }.map {
            LocalNet(ni.name, it.address.address, it.networkPrefixLength.toInt(), it.broadcast)
        }
    }
} catch (_: Exception) { emptyList() }

/**
 * UDP yayin kesfi: her ayakta IPv4 arayuzunun yayin adresine ve 255.255.255.255'e istek yollar.
 * Ilk 5 sn saniyede bir, sonra 10 sn'de bir. Yanit kaynagi adres = Mac adresi.
 */
class UdpDiscovery(
    private val now: () -> Long,
    private val onFound: (MacService) -> Unit,
    private val onTick: () -> Unit,
) {
    fun launch(scope: CoroutineScope) = scope.launch(Dispatchers.IO) {
        val sock = try {
            DatagramSocket(null).apply { reuseAddress = true; broadcast = true; soTimeout = 500; bind(InetSocketAddress(0)) }
        } catch (_: Exception) { return@launch }
        try {
            val sender = launch {
                val req = UdpCodec.request()
                var tick = 0
                while (isActive) {
                    val targets = LinkedHashSet<InetAddress>()
                    for (n in localNets()) {
                        targets += n.broadcast ?: try { InetAddress.getByAddress(UdpCodec.broadcastOf(n.ip, n.prefix)) } catch (_: Exception) { continue }
                    }
                    try { targets += InetAddress.getByName("255.255.255.255") } catch (_: Exception) { }
                    for (t in targets) try { sock.send(DatagramPacket(req, req.size, t, UdpCodec.PORT)) } catch (_: Exception) { }
                    onTick()
                    tick++
                    delay(if (tick < 5) 1_000 else 10_000)
                }
            }
            val buf = ByteArray(2048)
            while (isActive) {
                val p = DatagramPacket(buf, buf.size)
                try { sock.receive(p) } catch (_: java.net.SocketTimeoutException) { continue } catch (_: Exception) { break }
                val r = UdpCodec.parseReply(p.data, p.length) ?: continue
                val addr = p.address ?: continue
                val hotspot = localNets().any { n -> UdpCodec.isHotspotName(n.ifName) && sameSubnet(n, addr) }
                onFound(MacService("udp:${r.id}", r.id, r.name, addr, r.port, if (hotspot) MacSource.HOTSPOT else MacSource.LAN, now()))
            }
            sender.cancel()
        } finally {
            sock.close()
        }
    }

    private fun sameSubnet(n: LocalNet, a: InetAddress): Boolean {
        val b = a.address
        if (b.size != 4) return false
        val bc = UdpCodec.broadcastOf(n.ip, n.prefix)
        val nb = UdpCodec.broadcastOf(b, n.prefix)
        return bc.contentEquals(nb)
    }
}
