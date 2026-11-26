package com.nabiz.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.security.MessageDigest
import kotlin.concurrent.thread

/** Aktar (docs/protokol.md bolum 13): vektor, cerceve, devam, SHA uyumsuzlugu, bastan sona akis. */
class AktarTest {
    private fun vectors(): Map<*, *> {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null) {
            val f = File(dir, "docs/fixtures/vectors.json")
            if (f.isFile) return (PeerJson.parse(f.readText()) as Map<*, *>)["aktar"] as Map<*, *>
            dir = dir.parentFile
        }
        throw AssertionError("vectors.json bulunamadi")
    }

    @Test fun keyDerivationVector() {
        val v = vectors()
        val keys = AktarCrypto.deriveKeys(hexToBytes(v["ikm"] as String), v["aid"] as String)
        assertEquals(v["senderToReceiver"], keys.senderToReceiver.toHexLower())
        assertEquals(v["receiverToSender"], keys.receiverToSender.toHexLower())
    }

    @Test fun dataPacketVector() {
        val v = vectors()
        val keys = AktarCrypto.deriveKeys(hexToBytes(v["ikm"] as String), v["aid"] as String)
        val plain = AktarFraming.dataPlain((v["fid"] as Number).toInt(), (v["ofset"] as Number).toLong(), hexToBytes(v["bayt"] as String))
        assertEquals(v["plaintext"], plain.toHexLower())
        assertEquals(v["packet"], PeerAead.seal(keys.senderToReceiver, 1, plain).toHexLower())
        val parsed = AktarFraming.parse(PeerAead.open(keys.senderToReceiver, hexToBytes(v["packet"] as String)).second) as AktarFrame.Data
        assertEquals(1, parsed.fid)
        assertEquals(65536L, parsed.ofset)
        assertEquals(v["bayt"], parsed.buf.copyOfRange(parsed.off, parsed.off + parsed.len).toHexLower())
    }

    @Test fun framingRoundTripAndLimits() {
        val data = ByteArray(1000) { it.toByte() }
        val f = AktarFraming.parse(AktarFraming.dataPlain(65535, 1L shl 40, data)) as AktarFrame.Data
        assertEquals(65535, f.fid); assertEquals(1L shl 40, f.ofset); assertEquals(1000, f.len)
        val j = AktarFraming.parse(AktarFraming.jsonPlain("{\"t\":\"devam\"}")) as AktarFrame.Json
        assertEquals("{\"t\":\"devam\"}", j.text)
        try { AktarFraming.dataPlain(1, 0, ByteArray(AktarFraming.MAX_DATA + 1)); fail() } catch (_: IllegalArgumentException) { }
        try { AktarFraming.parse(byteArrayOf(0x7f)); fail() } catch (_: PeerProtocolException) { }
        try { AktarFraming.parse(byteArrayOf(0x02, 0, 1)); fail() } catch (_: PeerProtocolException) { }
    }

    @Test fun controlCodec() {
        val d = AktarControlCodec.decode(AktarControlCodec.encode(AktarControl.Devam(mapOf(0 to 10L, 3 to 99L))))
        assertEquals(AktarControl.Devam(mapOf(0 to 10L, 3 to 99L)), d)
        assertEquals(AktarControl.DosyaSon(2, "ab"), AktarControlCodec.decode(AktarControlCodec.encode(AktarControl.DosyaSon(2, "AB"))))
        assertTrue(AktarControlCodec.decode("{\"t\":\"gelecek\"}") is AktarControl.Unknown)
    }

    // --- Bastan sona akis (bellek icinde) ------------------------------------------------------------------------

    private class Mem : AktarStorage {
        val parts = HashMap<String, MemPartial>()
        val done = HashMap<Int, ByteArray>()
        override fun freeBytes() = Long.MAX_VALUE / 2
        override fun partial(aid: String, f: AktarFile) = parts.getOrPut("$aid/${f.fid}") { MemPartial(f.fid, done) }
    }

    private class MemPartial(val fid: Int, val done: HashMap<Int, ByteArray>) : AktarPartial {
        var buf = ByteArrayOutputStream()
        override val length: Long get() = buf.size().toLong()
        override fun openRead() = ByteArrayInputStream(buf.toByteArray())
        override fun openAppend() = buf
        override fun reset() { buf = ByteArrayOutputStream() }
        override fun commit(): String { done[fid] = buf.toByteArray(); return "mem/$fid" }
        override fun discard() { buf = ByteArrayOutputStream() }
    }

    private fun sha(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).toHexLower()

    private class Pipe {
        val aIn = PipedInputStream(1 shl 20); val bOut = PipedOutputStream(aIn)   // b -> a
        val bIn = PipedInputStream(1 shl 20); val aOut = PipedOutputStream(bIn)   // a -> b
    }

    private fun channels(aid: String): Pair<AktarSecureChannel, AktarSecureChannel> {
        val okm = ByteArray(64) { (it * 3).toByte() }
        val k = AktarCrypto.deriveKeys(okm, aid)
        val p = Pipe()
        val (sw, sr) = AktarCrypto.keysFor(AktarRole.SENDER, k)
        val (rw, rr) = AktarCrypto.keysFor(AktarRole.RECEIVER, k)
        return AktarSecureChannel(p.aIn, p.aOut, sw, sr) to AktarSecureChannel(p.bIn, p.bOut, rw, rr)
    }

    private val big = ByteArray(1_300_000) { (it * 7 + it / 251).toByte() }   // 3 veri cercevesi
    private val small = "Nabız Aktar".toByteArray()
    private val files = listOf(AktarFile(0, "a.bin", big.size.toLong()), AktarFile(1, "b.txt", small.size.toLong()))
    private fun open(f: AktarFile) = ByteArrayInputStream(if (f.fid == 0) big else small)

    @Test fun endToEndTransfer() {
        val (s, r) = channels("aid-1")
        val mem = Mem()
        val receiver = AktarReceiver("aid-1", files, mem)
        val sender = AktarSender(files, ::open)
        var ok = false
        val rt = thread { ok = receiver.serve(r); sender.complete() }
        sender.run(s)
        rt.join()
        assertTrue(ok)
        assertTrue(receiver.isFinished)
        assertEquals("tamam", receiver.result().sonuc)
        assertArrayEquals(big, mem.done[0]); assertArrayEquals(small, mem.done[1])
    }

    @Test fun resumeContinuesFromOffset() {
        val mem = Mem()
        // Onceki baglantida a.bin'in ilk 600000 bayti yazilmis.
        mem.partial("aid-2", files[0]).openAppend().write(big, 0, 600_000)
        val receiver = AktarReceiver("aid-2", files, mem)
        assertEquals(mapOf(0 to 600_000L), receiver.resumeOffsets())
        val (s, r) = channels("aid-2")
        val sentFrom = ArrayList<Long>()
        val sender = AktarSender(files, ::open, onProgress = { fid, sent -> if (fid == 0) sentFrom += sent })
        val rt = thread { receiver.serve(r); sender.complete() }
        sender.run(s)
        rt.join()
        assertTrue(receiver.isFinished)
        assertArrayEquals(big, mem.done[0])
        // Yalniz kalan kisim yollandi: ilk ilerleme 600000'in uzerinde.
        assertTrue(sentFrom.first() > 600_000L)
    }

    @Test fun shaMismatchRetriesThenFails() {
        val mem = Mem()
        val f = listOf(AktarFile(0, "x", 5))
        val rc = AktarReceiver("a", f, mem, maxTries = 2)
        rc.onData(0, 0, byteArrayOf(1, 2, 3, 4, 5), 0, 5)
        assertEquals(FileEnd.RETRY, rc.onFileEnd(0, "00"))
        assertEquals(0L, mem.partial("a", f[0]).length)           // bastan istenir
        rc.onData(0, 0, byteArrayOf(1, 2, 3, 4, 5), 0, 5)
        assertEquals(FileEnd.FAILED, rc.onFileEnd(0, "00"))
        assertEquals(listOf(0), rc.result().hatali)
        assertEquals("hata", rc.result().sonuc)
    }

    @Test fun badOffsetAndOversizeAreProtocolErrors() {
        val rc = AktarReceiver("a", listOf(AktarFile(0, "x", 4)), Mem())
        try { rc.onData(0, 2, byteArrayOf(1), 0, 1); fail() } catch (_: PeerProtocolException) { }
        try { rc.onData(0, 0, ByteArray(5), 0, 5); fail() } catch (_: PeerProtocolException) { }
        try { rc.onData(9, 0, ByteArray(1), 0, 1); fail() } catch (_: PeerProtocolException) { }
    }

    @Test fun replayedPacketRejected() {
        val keys = AktarCrypto.deriveKeys(ByteArray(64), "r")
        val sealer = PeerSealer(keys.senderToReceiver)
        val p = sealer.seal(AktarFraming.jsonPlain("{}"))
        val opener = PeerOpener(keys.senderToReceiver)
        opener.open(p)
        try { opener.open(p); fail() } catch (_: Exception) { }
    }

    @Test fun namesAndSpace() {
        assertEquals("dosya", AktarNames.sanitize("../.."))
        assertEquals("a.jpg", AktarNames.sanitize("x/../a.jpg"))
        assertEquals("a (2).jpg", AktarNames.unique("a.jpg") { it == "a.jpg" })
        assertFalse(AktarSpace.enough(100, 100))
        assertTrue(AktarSpace.enough(100, 100 + AktarSpace.RESERVE))
    }
}
