package com.nabiz.android.peer

import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer

// docs/protokol.md bolum 13: sifreli acik metnin ilk baytı tur, 0x01 JSON kontrol, 0x02 veri.

/** Cozulmus acik metin. Veri bayt'lari `buf[off, off+len)` araligindadir (kopyalanmaz). */
sealed class AktarFrame {
    class Json(val text: String) : AktarFrame()
    class Data(val fid: Int, val ofset: Long, val buf: ByteArray, val off: Int, val len: Int) : AktarFrame()
}

object AktarFraming {
    const val KIND_JSON: Byte = 0x01
    const val KIND_DATA: Byte = 0x02
    /** Bir veri cercevesindeki en cok dosya baytı (512 KiB). */
    const val MAX_DATA = 512 * 1024
    /** tur(1) + fid(2) + ofset(8). */
    const val DATA_HEADER = 11

    fun jsonPlain(text: String): ByteArray = byteArrayOf(KIND_JSON) + text.toByteArray(Charsets.UTF_8)

    /** `0x02 || fid(u16 BE) || ofset(u64 BE) || bayt`. */
    fun dataPlain(fid: Int, ofset: Long, bytes: ByteArray, off: Int = 0, len: Int = bytes.size): ByteArray {
        require(fid in 0..0xFFFF) { "fid gecersiz" }
        require(ofset >= 0) { "ofset gecersiz" }
        require(len in 0..MAX_DATA) { "veri uzunlugu gecersiz" }
        val bb = ByteBuffer.allocate(DATA_HEADER + len)
        bb.put(KIND_DATA).putShort(fid.toShort()).putLong(ofset).put(bytes, off, len)
        return bb.array()
    }

    fun parse(plain: ByteArray): AktarFrame {
        if (plain.isEmpty()) throw PeerProtocolException("bos cerceve")
        return when (plain[0]) {
            KIND_JSON -> AktarFrame.Json(String(plain, 1, plain.size - 1, Charsets.UTF_8))
            KIND_DATA -> {
                if (plain.size < DATA_HEADER) throw PeerProtocolException("veri cercevesi kisa")
                val bb = ByteBuffer.wrap(plain, 1, 10)
                val fid = bb.short.toInt() and 0xFFFF
                val ofset = bb.long
                val len = plain.size - DATA_HEADER
                if (ofset < 0 || len > MAX_DATA) throw PeerProtocolException("veri cercevesi gecersiz")
                AktarFrame.Data(fid, ofset, plain, DATA_HEADER, len)
            }
            else -> throw PeerProtocolException("bilinmeyen cerceve turu")
        }
    }
}

/**
 * Sifreli veri baglantisi (akis uzerinde, aga bagli degil): her cerceve `uzunluk(4) || sayac8 || sifreliMetin || etiket`.
 * Yazma iplik guvenlidir (sayac sirasi = yazma sirasi). Okuma tek iplikten yapilir.
 */
class AktarSecureChannel(
    private val input: InputStream,
    private val output: OutputStream,
    sealKey: ByteArray,
    openKey: ByteArray,
) {
    private val sealer = PeerSealer(sealKey)
    private val opener = PeerOpener(openKey)
    private val writeLock = Any()

    fun sendControl(c: AktarControl) = writeFrame(AktarFraming.jsonPlain(AktarControlCodec.encode(c)))

    fun sendData(fid: Int, ofset: Long, bytes: ByteArray, off: Int, len: Int) =
        writeFrame(AktarFraming.dataPlain(fid, ofset, bytes, off, len))

    private fun writeFrame(plain: ByteArray) {
        synchronized(writeLock) {
            val packet = sealer.seal(plain)
            // Tek write: uzunluk + paket birlikte (toplu yazim).
            val out = ByteBuffer.allocate(4 + packet.size).putInt(packet.size).put(packet).array()
            output.write(out)
            output.flush()
        }
    }

    /** Sonraki cerceve; baglanti temiz kapandiysa null. Bozuk/tekrar/dogrulanamayan paket: PeerCryptoException / PeerProtocolException. */
    fun receive(): AktarFrame? {
        val payload = AktarFrameReader.read(input) ?: return null
        return AktarFraming.parse(opener.open(payload))
    }

    /** Kontrol mesaji bekler (veri cercevesi gelirse protokol hatasi). */
    fun receiveControl(): AktarControl? {
        val f = receive() ?: return null
        if (f !is AktarFrame.Json) throw PeerProtocolException("kontrol mesaji bekleniyordu")
        return AktarControlCodec.decode(f.text)
    }
}

/** Bolum 2 cercevesini akistan okur (1..1 048 576 bayt yuk). */
object AktarFrameReader {
    /** Akis cerceve basinda temiz biterse null; ortasinda biterse EOFException. */
    fun read(input: InputStream): ByteArray? {
        val head = ByteArray(4)
        var got = 0
        while (got < 4) {
            val n = input.read(head, got, 4 - got)
            if (n < 0) { if (got == 0) return null else throw EOFException("cerceve basligi yarim") }
            got += n
        }
        val n = ByteBuffer.wrap(head).int.toLong() and 0xFFFFFFFFL
        if (n < 1 || n > PeerFraming.MAX_PAYLOAD) throw PeerProtocolException("cerceve uzunlugu gecersiz")
        val buf = ByteArray(n.toInt())
        var off = 0
        while (off < buf.size) {
            val r = input.read(buf, off, buf.size - off)
            if (r < 0) throw EOFException("cerceve yarim")
            off += r
        }
        return buf
    }

    /** Duz (sifresiz) tek cerceve yazar: ilk `aktar.baglan`. */
    fun writePlain(out: OutputStream, payload: ByteArray) {
        try {
            out.write(PeerFraming.encode(payload))
            out.flush()
        } catch (e: IOException) {
            throw e
        }
    }
}
