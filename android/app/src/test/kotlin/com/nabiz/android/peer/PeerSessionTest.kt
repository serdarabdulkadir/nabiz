package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PeerSessionTest {
    private class Side(role: PeerRole, name: String, pinned: ByteArray?, key: Pair<ByteArray, ByteArray>, nonceSeed: Int) {
        val pub = key.second
        val events = ArrayList<PeerEvent>()
        val session = PeerSession(
            role, P256.privateKeyFromRaw(key.first), key.second, name, pinned, ByteArray(16) { (nonceSeed + it).toByte() },
            PeerMessage.Hello(name, "1", 1, "id-$name", if (role == PeerRole.MAC) "mac" else "android"),
        )
        fun out(): List<ByteArray> = events.filterIsInstance<PeerEvent.Send>().map { it.bytes }.also { events.removeAll { e -> e is PeerEvent.Send } }
    }

    private fun pump(a: Side, b: Side) {
        repeat(6) {
            for (x in a.out()) b.events += b.session.receive(x)
            for (x in b.out()) a.events += a.session.receive(x)
        }
    }

    private fun keys() = P256.generate() to P256.generate()

    @Test fun firstPairingShowsSameSasAndThenExchangesStats() {
        val (mk, pk) = keys()
        val mac = Side(PeerRole.MAC, "Mac", null, mk, 0xa0)
        val phone = Side(PeerRole.TELEFON, "Tel", null, pk, 0xb0)
        mac.events += mac.session.start(); phone.events += phone.session.start()
        pump(mac, phone)
        val s1 = mac.events.filterIsInstance<PeerEvent.SasRequired>().single().code
        val s2 = phone.events.filterIsInstance<PeerEvent.SasRequired>().single().code
        assertEquals(s1, s2); assertEquals(6, s1.length)
        mac.events += mac.session.confirmSas(true); phone.events += phone.session.confirmSas(true)
        pump(mac, phone)
        assertTrue(phone.events.any { it is PeerEvent.Paired })
        assertTrue(phone.events.filterIsInstance<PeerEvent.Received>().any { it.message is PeerMessage.Hello })
        phone.events += phone.session.send(PeerMessage.Stats(Snapshot(1, uptime = 5)))
        pump(mac, phone)
        assertNotNull(mac.events.filterIsInstance<PeerEvent.Received>().map { it.message }.filterIsInstance<PeerMessage.Stats>().firstOrNull())
    }

    @Test fun rejectedSasClosesAndPinnedKeyMismatchCloses() {
        val (mk, pk) = keys()
        val mac = Side(PeerRole.MAC, "Mac", null, mk, 1)
        val phone = Side(PeerRole.TELEFON, "Tel", null, pk, 2)
        mac.events += mac.session.start(); phone.events += phone.session.start()
        pump(mac, phone)
        val ev = phone.session.confirmSas(false)
        assertTrue(ev.any { it is PeerEvent.Closed && it.reason == CloseReason.SAS_REJECTED })

        val other = P256.generate()
        val mac2 = Side(PeerRole.MAC, "Mac", null, mk, 1)
        val phone2 = Side(PeerRole.TELEFON, "Tel", other.second, pk, 2)   // yanlis pin
        mac2.events += mac2.session.start(); phone2.events += phone2.session.start()
        pump(mac2, phone2)
        assertTrue(phone2.events.any { it is PeerEvent.Closed && it.reason == CloseReason.KEY_CHANGED })
    }

    @Test fun pinnedSkipsSas() {
        val (mk, pk) = keys()
        val mac = Side(PeerRole.MAC, "Mac", pk.second, mk, 1)
        val phone = Side(PeerRole.TELEFON, "Tel", mk.second, pk, 2)
        mac.events += mac.session.start(); phone.events += phone.session.start()
        pump(mac, phone)
        assertTrue(phone.events.any { it is PeerEvent.Ready })
        assertTrue(phone.events.none { it is PeerEvent.SasRequired })
    }

    @Test fun sameRoleClosed() {
        val (mk, pk) = keys()
        val a = Side(PeerRole.TELEFON, "A", null, mk, 1)
        val b = Side(PeerRole.TELEFON, "B", null, pk, 2)
        a.events += a.session.start(); b.events += b.session.start()
        pump(a, b)
        assertTrue(a.events.any { it is PeerEvent.Closed && it.reason == CloseReason.ROLE })
    }
}
