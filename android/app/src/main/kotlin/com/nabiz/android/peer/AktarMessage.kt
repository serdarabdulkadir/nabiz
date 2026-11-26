package com.nabiz.android.peer

// docs/protokol.md bolum 13: Aktar mesaj icerikleri.

/** `fid` 0'dan ardisik; `ad` yalniz dosya adi; `tur` bilinmiyorsa application/octet-stream; `degisme` epoch sn. */
data class AktarFile(val fid: Int, val ad: String, val boyut: Long, val tur: String = "application/octet-stream", val degisme: Long? = null)

/** aktar.teklif/yanit/iptal/bitti icin ortak (PeerMessage'a bagli) kodlayici yardimcilari. */
internal object AktarCodec {
    fun fileMap(f: AktarFile): Map<String, Any?> {
        val m = hashMapOf<String, Any?>("fid" to f.fid, "ad" to f.ad, "boyut" to f.boyut, "tur" to f.tur)
        f.degisme?.let { m["degisme"] = it }
        return m
    }

    fun file(f: Fields) = AktarFile(
        f.int("fid"), f.str("ad"), f.long("boyut"), f.strOpt("tur") ?: "application/octet-stream", f.longOpt("degisme"),
    )

    fun files(list: List<*>?): List<AktarFile> =
        list.orEmpty().map { file(Fields(it as? Map<*, *> ?: throw PeerProtocolException("dosya nesne degil"))) }
}

/** Veri baglantisindaki kontrol mesajlari (tur baytı 0x01, sifreli); ve ilk duz `aktar.baglan` cercevesi. */
sealed class AktarControl {
    /** Telefonun ilk (duz JSON) cercevesi. */
    data class Baglan(val aid: String) : AktarControl()
    /** Alici -> gonderen, ilk sifreli mesaj: dosya basina kaldigi bayt (yarim dosya yoksa bos). */
    data class Devam(val ofsetler: Map<Int, Long>) : AktarControl()
    /** Gonderen: dosya bitti, tum dosyanin SHA-256 degeri (kucuk harf hex). */
    data class DosyaSon(val fid: Int, val sha256: String) : AktarControl()
    /** Alici: hash uymadi, dosya bastan istenir. */
    data class DosyaHata(val fid: Int) : AktarControl()
    data class Unknown(val type: String) : AktarControl()
}

object AktarControlCodec {
    fun toMap(c: AktarControl): Map<String, Any?> = when (c) {
        is AktarControl.Baglan -> mapOf("t" to "aktar.baglan", "aid" to c.aid)
        is AktarControl.Devam -> mapOf("t" to "devam", "ofsetler" to c.ofsetler.entries.associate { it.key.toString() to it.value })
        is AktarControl.DosyaSon -> mapOf("t" to "dosya.son", "fid" to c.fid, "sha256" to c.sha256)
        is AktarControl.DosyaHata -> mapOf("t" to "dosya.hata", "fid" to c.fid)
        is AktarControl.Unknown -> mapOf("t" to c.type)
    }

    fun encode(c: AktarControl): String = PeerJson.write(toMap(c))

    /** Bozuk JSON / eksik alan: PeerProtocolException. Bilinmeyen `t`: Unknown (olumcul degil). */
    fun decode(text: String): AktarControl {
        val root = PeerJson.parse(text) as? Map<*, *> ?: throw PeerProtocolException("mesaj nesne degil")
        val o = Fields(root)
        return when (val t = o.str("t")) {
            "aktar.baglan" -> AktarControl.Baglan(o.str("aid"))
            "devam" -> AktarControl.Devam(
                o.mapOpt("ofsetler").orEmpty().entries.mapNotNull { (k, v) ->
                    val fid = (k as? String)?.toIntOrNull() ?: return@mapNotNull null
                    val n = (v as? Number)?.toLong() ?: return@mapNotNull null
                    fid to n
                }.toMap(),
            )
            "dosya.son" -> AktarControl.DosyaSon(o.int("fid"), o.str("sha256").lowercase())
            "dosya.hata" -> AktarControl.DosyaHata(o.int("fid"))
            else -> AktarControl.Unknown(t)
        }
    }
}
