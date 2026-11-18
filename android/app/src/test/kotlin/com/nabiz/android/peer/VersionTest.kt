package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VersionTest {
    @Test fun mismatchedHsVersionClosesWithVersionReason() {
        val (mk, pk) = P256.generate() to P256.generate()
        val phone = PeerSession(
            PeerRole.TELEFON, P256.privateKeyFromRaw(pk.first), pk.second, "Tel", null, ByteArray(16),
            PeerMessage.Hello("Tel", "1", 1, "id", "android"),
        )
        val hs = """{"t":"hs","v":2,"rol":"mac","pub":"${java.util.Base64.getEncoder().encodeToString(mk.second)}","nonce":"${java.util.Base64.getEncoder().encodeToString(ByteArray(16))}","ad":"M"}"""
        val ev = phone.receive(PeerFraming.encode(hs.toByteArray()))
        assertTrue(ev.any { it is PeerEvent.Closed && it.reason == CloseReason.VERSION })
        assertEquals(2, phone.peerVersion)
    }

    @Test fun longestBackoffStaysLongest() {
        val b = ReconnectBackoff()
        assertEquals(30_000L, b.longest())
        assertEquals(30_000L, b.next())
    }

    @Test fun versionReasonTextMentionsVersion() {
        assertEquals("Mac'teki Nabız farklı sürümde (v2). İki uygulamayı da güncelleyin.", com.nabiz.android.ui.reasonText(LinkReason.VERSION, 2))
    }
}
