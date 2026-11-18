package com.nabiz.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class PeerFramingTest {
    @Test fun frameVector() {
        assertEquals("00000003010203", PeerFraming.encode(byteArrayOf(1, 2, 3)).toHexLower())
    }

    @Test fun fragmentedAndCoalescedFrames() {
        val a = PeerFraming.encode(byteArrayOf(1, 2, 3))
        val b = PeerFraming.encode(byteArrayOf(9))
        val all = a + b
        val buf = PeerFrameBuffer()
        val out = ArrayList<ByteArray>()
        for (x in all) out += buf.append(byteArrayOf(x))   // bayt bayt
        assertEquals(2, out.size)
        assertArrayEquals(byteArrayOf(1, 2, 3), out[0]); assertArrayEquals(byteArrayOf(9), out[1])
        val both = PeerFrameBuffer().append(all)           // tek seferde
        assertEquals(2, both.size)
    }

    @Test fun invalidLengthsAreFatal() {
        for (hex in listOf("00000000", "00100001")) {
            try { PeerFrameBuffer().append(hexToBytes(hex)); fail("gecersiz uzunluk kabul edildi") } catch (_: PeerProtocolException) { }
        }
    }
}
