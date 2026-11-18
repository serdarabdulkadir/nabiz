package com.nabiz.android.peer

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/** Uzak adres ("host" ya da "host:port", varsayilan port 47821). Saf ayristirma, JVM birim testli. */
data class RemoteAddress(val host: String, val port: Int) {
    companion object {
        const val DEFAULT_PORT = 47821

        fun parse(text: String?): RemoteAddress? {
            val t = text?.trim().orEmpty()
            if (t.isEmpty()) return null
            if (t.startsWith("[")) {
                val end = t.indexOf(']')
                if (end < 2) return null
                val rest = t.substring(end + 1)
                val port = when {
                    rest.isEmpty() -> DEFAULT_PORT
                    rest.startsWith(":") -> rest.substring(1).toIntOrNull() ?: return null
                    else -> return null
                }
                return if (port in 1..65535) RemoteAddress(t.substring(1, end), port) else null
            }
            val colons = t.count { it == ':' }
            if (colons > 1) return RemoteAddress(t, DEFAULT_PORT) // bos IPv6
            if (colons == 1) {
                val host = t.substringBefore(':')
                val port = t.substringAfter(':').toIntOrNull() ?: return null
                return if (host.isNotEmpty() && port in 1..65535) RemoteAddress(host, port) else null
            }
            return RemoteAddress(t, DEFAULT_PORT)
        }

        /** Cozumleme (IO'da) + TCP baglanti denemesi; el sikisma yapmaz. */
        suspend fun probe(text: String?, timeoutMs: Int = 5_000): Boolean {
            val a = parse(text) ?: return false
            return withContext(Dispatchers.IO) {
                try {
                    val ip = InetAddress.getByName(a.host)
                    Socket().use { it.connect(InetSocketAddress(ip, a.port), timeoutMs) }
                    true
                } catch (_: Exception) { false }
            }
        }
    }
}
