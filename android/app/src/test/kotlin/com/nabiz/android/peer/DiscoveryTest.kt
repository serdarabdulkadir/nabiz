package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class DiscoveryTest {
    private fun svc(id: String, src: MacSource, seen: Long, host: String = "10.0.0.2", port: Int = 5000, name: String = "Mac $id") =
        MacService("s:$id", id, name, InetAddress.getByName(host), port, src, seen)

    @Test fun mergeReplacesById() {
        val a = DiscoveryMerge.merge(emptyList(), svc("1", MacSource.LAN, 1))
        val b = DiscoveryMerge.merge(a, svc("1", MacSource.HOTSPOT, 2, port = 6000))
        assertEquals(1, b.size)
        assertEquals(6000, b[0].port)
        assertEquals(MacSource.HOTSPOT, b[0].source)
    }

    @Test fun lastAddressDoesNotOverrideRealDiscovery() {
        val a = DiscoveryMerge.merge(emptyList(), svc("1", MacSource.LAN, 1, port = 5000))
        val b = DiscoveryMerge.merge(a, svc("1", MacSource.LAST, 9, port = 1111))
        assertEquals(5000, b[0].port)
        // gercek kesif LAST'in yerini alir
        val c = DiscoveryMerge.merge(DiscoveryMerge.merge(emptyList(), svc("2", MacSource.LAST, 1)), svc("2", MacSource.LAN, 2, port = 7000))
        assertEquals(MacSource.LAN, c[0].source); assertEquals(7000, c[0].port)
    }

    @Test fun pruneDropsAfter60s() {
        val l = listOf(svc("1", MacSource.LAN, 0), svc("2", MacSource.LAN, 50_000))
        assertEquals(listOf("2"), DiscoveryMerge.prune(l, 70_000).map { it.id })
        assertEquals(2, DiscoveryMerge.prune(l, 60_000).size)
    }

    @Test fun dropLastOnlyRemovesLast() {
        val l = listOf(svc("1", MacSource.LAST, 1), svc("2", MacSource.LAN, 1))
        assertEquals(listOf("2"), DiscoveryMerge.dropLast(l, "1").map { it.id })
        assertEquals(2, DiscoveryMerge.dropLast(l, "2").size)
    }

    @Test fun requestIsKesifV1() {
        assertEquals("""{"t":"kesif","v":1}""", String(UdpCodec.request()))
    }

    @Test fun replyParsing() {
        val r = UdpCodec.parseReply(UdpCodec.encodeReply("abc", "MacBook", 47821))!!
        assertEquals("abc", r.id); assertEquals("MacBook", r.name); assertEquals(47821, r.port)
        assertNull(UdpCodec.parseReply("""{"t":"kesif.yanit","v":2,"id":"a","ad":"x","port":1}""".toByteArray()))
        assertNull(UdpCodec.parseReply("""{"t":"kesif","v":1}""".toByteArray()))
        assertNull(UdpCodec.parseReply("""{"t":"kesif.yanit","v":1,"id":"a","ad":"x","port":0}""".toByteArray()))
        assertNull(UdpCodec.parseReply("bozuk".toByteArray()))
    }

    @Test fun broadcastAddress() {
        assertEquals("10.171.49.255", InetAddress.getByAddress(UdpCodec.broadcastOf(byteArrayOf(10, -85, 49, 7), 24)).hostAddress)
        assertEquals("192.168.3.127", InetAddress.getByAddress(UdpCodec.broadcastOf(byteArrayOf(-64, -88, 3, 5), 25)).hostAddress)
        assertTrue(UdpCodec.isHotspotName("ap0")); assertTrue(!UdpCodec.isHotspotName("wlan0"))
    }
}
