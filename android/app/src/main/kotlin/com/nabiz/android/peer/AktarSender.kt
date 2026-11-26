package com.nabiz.android.peer

import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/**
 * Bir aktarimin gonderen tarafi (docs/protokol.md bolum 13). Dosyalar ORIJINAL bayt olarak, sirayla ve akisla gider
 * (bellekte yalniz bir 512 KiB parca). `run` bloklar; cagiran bir IO iplikten calistirir.
 */
class AktarSender(
    private val files: List<AktarFile>,
    /** Dosyanin ham baytlarini acar (ContentResolver.openInputStream); her cagri yeni akis. */
    private val open: (AktarFile) -> InputStream,
    /** fid, o dosyadan simdiye dek karsiya yazilan mutlak bayt. */
    private val onProgress: (fid: Int, sent: Long) -> Unit = { _, _ -> },
    private val isCancelled: () -> Boolean = { false },
) {
    private val resend = ConcurrentLinkedQueue<Int>()
    private val closed = CountDownLatch(1)

    /** Karsi taraf kontrol kanalindan `aktar.bitti` yolladi: bekleme biter. */
    fun complete() = closed.countDown()

    /**
     * Once alicinin `devam` mesajini bekler, sonra tum dosyalari yollar; bitince `bitti`/kapanisi bekler
     * (bu surede gelen `dosya.hata` istekleri bastan yollanir). Hata (IO, protokol) cagirana yayilir.
     */
    fun run(ch: AktarSecureChannel) {
        val first = ch.receiveControl() ?: throw IOException("baglanti devam gelmeden kapandi")
        val offsets = (first as? AktarControl.Devam)?.ofsetler ?: throw PeerProtocolException("ilk mesaj devam olmali")

        val reader = thread(isDaemon = true, name = "aktar-okuyucu") {
            try {
                while (true) {
                    val f = ch.receive() ?: break
                    if (f is AktarFrame.Json) {
                        val c = AktarControlCodec.decode(f.text)
                        if (c is AktarControl.DosyaHata) resend.add(c.fid)
                    }
                }
            } catch (_: Exception) {
                // Okuma koptu: gonderim tarafi yazarken zaten hata alir; bitti beklemesi de sona erer.
            } finally {
                closed.countDown()
            }
        }

        for (f in files) {
            if (isCancelled()) return
            val start = (offsets[f.fid] ?: 0L).let { if (it < 0 || it > f.boyut) 0L else it }
            sendFile(ch, f, start)
        }
        // Gonderim bitti: alicinin bitti mesajini (ya da baglanti kapanisini) bekle; dosya.hata gelirse o dosyayi bastan yolla.
        while (!isCancelled()) {
            val fid = resend.poll()
            if (fid != null) {
                files.firstOrNull { it.fid == fid }?.let { sendFile(ch, it, 0L) }
                continue
            }
            if (closed.await(100, TimeUnit.MILLISECONDS)) {
                // Kapanisla gelmis son istekler varsa onlari da isle.
                if (resend.isEmpty()) break
            }
        }
        reader.interrupt()
    }

    private fun sendFile(ch: AktarSecureChannel, f: AktarFile, start: Long) {
        val md = MessageDigest.getInstance("SHA-256")
        val buf = ByteArray(AktarFraming.MAX_DATA)
        open(f).use { ins ->
            var pos = 0L
            // Devam: onceki baytlar yollanmaz ama SHA-256 tum dosya uzerinden hesaplanir.
            while (pos < start) {
                val n = ins.read(buf, 0, minOf(buf.size.toLong(), start - pos).toInt())
                if (n < 0) throw IOException("dosya beklenenden kisa: ${f.ad}")
                md.update(buf, 0, n)
                pos += n
            }
            while (pos < f.boyut) {
                if (isCancelled()) return
                val n = ins.read(buf, 0, minOf(buf.size.toLong(), f.boyut - pos).toInt())
                if (n < 0) throw IOException("dosya beklenenden kisa: ${f.ad}")
                if (n == 0) continue
                md.update(buf, 0, n)
                ch.sendData(f.fid, pos, buf, 0, n)
                pos += n
                onProgress(f.fid, pos)
            }
        }
        ch.sendControl(AktarControl.DosyaSon(f.fid, md.digest().toHexLower()))
        onProgress(f.fid, f.boyut)
    }
}
