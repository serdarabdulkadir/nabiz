package com.nabiz.android.peer

import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

// docs/protokol.md bolum 13: alici mantigi. Aga ve Android'e bagimli degil; depolama `AktarStorage` arkasinda.

/** Yarim (henuz dogrulanmamis) dosya. Android'de MediaStore IS_PENDING kaydi, JVM/eski Android'de `.nabizpart` dosyasi. */
interface AktarPartial {
    /** Su ana dek yazilmis bayt. */
    val length: Long
    fun openRead(): InputStream
    /** Sona ekleyerek yazar (yoksa olusturur). */
    fun openAppend(): OutputStream
    /** Icerigi sifirlar (dosya bastan istenecek). */
    fun reset()
    /** Dosyayi son adina tasir; konum etiketi doner (uri ya da yol). */
    fun commit(): String
    fun discard()
}

interface AktarStorage {
    /** Yazilabilir bos yer (bayt). */
    fun freeBytes(): Long
    /** Ayni (aid, fid) icin her cagrida ayni yarim dosyayi doner (yeniden baglanmada devam icin). */
    fun partial(aid: String, f: AktarFile): AktarPartial
}

object AktarNames {
    private const val MAX_NAME = 150

    /** Yol ayiricilari, kontrol karakterleri ve `..` temizlenir; bos kalirsa "dosya". */
    fun sanitize(ad: String): String {
        var s = ad.substringAfterLast('/').substringAfterLast('\\')
        s = s.filter { it >= ' ' && it != '\u007f' }.trim()
        if (s.isEmpty() || s.all { it == '.' }) return "dosya"
        if (s.length > MAX_NAME) {
            val dot = s.lastIndexOf('.')
            val ext = if (dot > 0 && s.length - dot <= 16) s.substring(dot) else ""
            s = s.substring(0, s.length - ext.length).take(MAX_NAME - ext.length) + ext
        }
        return s
    }

    /** Ayni ad varsa " (2)", " (3)" ... uzantidan once eklenir. */
    fun unique(name: String, exists: (String) -> Boolean): String {
        if (!exists(name)) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 2
        while (i < 100_000) {
            val c = "$base ($i)$ext"
            if (!exists(c)) return c
            i++
        }
        return "$base (${System.currentTimeMillis()})$ext"
    }
}

object AktarSpace {
    /** Disk dolmasin diye birakilan pay. */
    const val RESERVE = 100L * 1024 * 1024

    /** Baştan yer kontrolu: kalan bayt + pay bos yere sigmali. `already`: zaten yazilmis yarim dosya baytlari. */
    fun enough(total: Long, free: Long, already: Long = 0): Boolean = (total - already).coerceAtLeast(0) + RESERVE <= free
}

/** `.nabizpart` dosyasi olarak yarim dosya (JVM testleri ve Android 9 ve alti icin). */
class FileAktarPartial(private val dir: File, private val finalName: String, partKey: String = "") : AktarPartial {
    /** `partKey` (aid + fid) eşzamanlı aynı adlı aktarımların aynı yarım dosyaya yazmasını önler. */
    private val part = File(dir, if (partKey.isEmpty()) "$finalName.nabizpart" else "$finalName.$partKey.nabizpart")

    override val length: Long get() = if (part.isFile) part.length() else 0L

    override fun openRead(): InputStream = if (part.isFile) FileInputStream(part) else ByteArrayInputStream(ByteArray(0))

    override fun openAppend(): OutputStream {
        dir.mkdirs()
        return FileOutputStream(part, true)
    }

    override fun reset() {
        if (part.isFile) FileOutputStream(part, false).close()
    }

    override fun commit(): String {
        dir.mkdirs()
        if (!part.isFile) part.createNewFile()
        val name = AktarNames.unique(finalName) { File(dir, it).exists() }
        val target = File(dir, name)
        if (!part.renameTo(target)) {
            part.copyTo(target, overwrite = false)
            part.delete()
        }
        return target.path
    }

    override fun discard() { part.delete() }
}

enum class FileEnd { OK, RETRY, FAILED, IGNORED }

/**
 * Bir aktarimin alici tarafi (tek `aid`). Ayni nesne yeniden baglanmalarda yasar: tamamlanan dosyalar ve yarim dosyalar korunur.
 * Tek iplikten kullanilir (baglanti dongusu).
 */
class AktarReceiver(
    val aid: String,
    val files: List<AktarFile>,
    private val storage: AktarStorage,
    private val maxTries: Int = 3,
    private val onProgress: (fid: Int, received: Long) -> Unit = { _, _ -> },
) {
    private class State(val file: AktarFile, val partial: AktarPartial) {
        var digest: MessageDigest? = null
        var out: OutputStream? = null
        var written = -1L
        var done = false
        var failed = false
        var tries = 0
        var location: String? = null
    }

    private val states: Map<Int, State> = files.associate { it.fid to State(it, storage.partial(aid, it)) }

    val isFinished: Boolean get() = states.values.all { it.done || it.failed }
    val failedFids: List<Int> get() = states.values.filter { it.failed }.map { it.file.fid }
    /** fid -> kayit konumu (tamamlananlar). */
    val locations: Map<Int, String> get() = states.values.filter { it.done }.associate { it.file.fid to it.location.orEmpty() }

    /** Dosya basina o ana dek kesinlesen/yarim baytlar (ilerleme gostergesi). */
    fun receivedBytes(): Long = states.values.sumOf { if (it.done) it.file.boyut else if (it.written >= 0) it.written else it.partial.length.coerceAtMost(it.file.boyut) }

    /** `devam.ofsetler`: yarim dosyanin kaldigi yer; biten dosya boyutunu bildirir; yoksa girdi yok. */
    fun resumeOffsets(): Map<Int, Long> {
        val m = LinkedHashMap<Int, Long>()
        for (s in states.values) {
            release(s)
            if (s.failed) continue
            if (s.done) { m[s.file.fid] = s.file.boyut; continue }
            var len = s.partial.length
            if (len > s.file.boyut) { s.partial.reset(); len = 0 }
            if (len > 0) m[s.file.fid] = len
        }
        return m
    }

    private fun release(s: State) {
        try { s.out?.close() } catch (_: Exception) { }
        s.out = null; s.digest = null; s.written = -1L
    }

    /** Baglanti koptu: acik akislar kapanir, yarim dosyalar kalir. */
    fun connectionLost() = states.values.forEach { release(it) }

    /** Vazgecildi / 10 dk doldu: yarim dosyalar silinir (biten dosyalar kalir). */
    fun abort() {
        for (s in states.values) {
            release(s)
            if (!s.done) s.partial.discard()
        }
    }

    private fun open(s: State) {
        var len = s.partial.length
        if (len > s.file.boyut) { s.partial.reset(); len = 0 }
        var md = MessageDigest.getInstance("SHA-256")
        if (len > 0) {
            var left = len
            val buf = ByteArray(256 * 1024)
            s.partial.openRead().use { ins ->
                while (left > 0) {
                    val n = ins.read(buf, 0, minOf(buf.size.toLong(), left).toInt())
                    if (n < 0) break
                    md.update(buf, 0, n)
                    left -= n
                }
            }
            if (left > 0) { s.partial.reset(); len = 0; md = MessageDigest.getInstance("SHA-256") }
        }
        s.digest = md
        s.out = s.partial.openAppend()
        s.written = len
    }

    /** Veri cercevesi. Ofset beklenenle uyusmazsa ya da boyut asilirsa protokol hatasi (olumcul). */
    fun onData(fid: Int, ofset: Long, buf: ByteArray, off: Int, len: Int) {
        val s = states[fid] ?: throw PeerProtocolException("bilinmeyen fid")
        if (s.done || s.failed) throw PeerProtocolException("dosya zaten bitti")
        if (s.written < 0) open(s)
        if (ofset != s.written) throw PeerProtocolException("ofset uyusmuyor")
        if (s.written + len > s.file.boyut) throw PeerProtocolException("dosya boyutu asildi")
        s.out!!.write(buf, off, len)
        s.digest!!.update(buf, off, len)
        s.written += len
        onProgress(fid, s.written)
    }

    /** `dosya.son`: SHA-256 ve boyut dogrulanir. Uymazsa RETRY (dosya.hata yollanir, bastan istenir); `maxTries` sonra FAILED. */
    fun onFileEnd(fid: Int, sha256: String): FileEnd {
        val s = states[fid] ?: throw PeerProtocolException("bilinmeyen fid")
        if (s.done || s.failed) return FileEnd.IGNORED
        if (s.written < 0) open(s)
        val actual = s.digest!!.digest().toHexLower()
        val ok = s.written == s.file.boyut && actual == sha256.lowercase()
        release(s)
        if (ok) {
            s.location = s.partial.commit()
            s.done = true
            onProgress(fid, s.file.boyut)
            return FileEnd.OK
        }
        s.tries++
        s.partial.reset()
        if (s.tries >= maxTries) {
            s.failed = true
            s.partial.discard()
            return FileEnd.FAILED
        }
        return FileEnd.RETRY
    }

    fun result(): PeerMessage.AktarBitti {
        val bad = failedFids
        return PeerMessage.AktarBitti(aid, if (bad.isEmpty()) "tamam" else "hata", bad)
    }

    /**
     * Veri baglantisini surer: once `devam`, sonra cerceveler. Tum dosyalar bitince true; baglanti temiz kapanirsa false.
     * Aga/IO hatalari cagirana yayilir (cagiran `connectionLost()` cagirir ve yeniden dener).
     */
    fun serve(ch: AktarSecureChannel): Boolean {
        ch.sendControl(AktarControl.Devam(resumeOffsets()))
        if (isFinished) return true
        while (true) {
            val f = ch.receive() ?: return false
            when (f) {
                is AktarFrame.Data -> onData(f.fid, f.ofset, f.buf, f.off, f.len)
                is AktarFrame.Json -> {
                    val c = AktarControlCodec.decode(f.text)
                    if (c is AktarControl.DosyaSon && onFileEnd(c.fid, c.sha256) == FileEnd.RETRY) ch.sendControl(AktarControl.DosyaHata(c.fid))
                }
            }
            if (isFinished) return true
        }
    }
}
