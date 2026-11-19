package com.nabiz.android.ui

import com.nabiz.android.peer.AiLimit
import com.nabiz.android.peer.AiProvider
import java.time.Instant
import java.time.ZoneId

/** AI sekmesi icin saf bicimlendirme (docs/protokol.md bolum 12). */
object AiFormat {
    /**
     * On yuze giren iki limit: 1. ilk genel limit (kisa pencere); 2. ikinci genel limit, ama genel olmayan bir limit
     * %90+ ve ikinci genelden doluysa en dolu o. Genel limit yetmezse en dolu digerleriyle tamamlanir.
     */
    fun frontLimits(limits: List<AiLimit>): List<AiLimit> {
        val general = limits.filter { it.genel }
        val first = general.firstOrNull() ?: limits.maxByOrNull { it.yuzde } ?: return emptyList()
        val secondGeneral = general.getOrNull(1)
        val hot = limits.filter { !it.genel && it !== first && it.yuzde >= 90 }.maxByOrNull { it.yuzde }
        val second = when {
            hot != null && (secondGeneral == null || hot.yuzde > secondGeneral.yuzde) -> hot
            secondGeneral != null -> secondGeneral
            else -> limits.filter { it !== first }.maxByOrNull { it.yuzde }
        }
        return listOfNotNull(first, second)
    }

    /** "2 sa 10 dk", "3 g 4 sa", "45 dk"; 1 dakikadan azsa "1 dk'dan az". */
    fun remaining(seconds: Long): String {
        if (seconds < 60) return "1 dk'dan az"
        val d = seconds / 86_400
        val h = seconds % 86_400 / 3_600
        val m = seconds % 3_600 / 60
        return when {
            d > 0 -> if (h > 0) "$d g $h sa" else "$d g"
            h > 0 -> if (m > 0) "$h sa $m dk" else "$h sa"
            else -> "$m dk"
        }
    }

    /** Sayinin okunusuna gore -da/-de/-ta/-te (0..59 dakika ya da 0..23 saat). */
    fun suffix(n: Int): String {
        if (n % 10 == 0) return when (n) { 0, 10, 30 -> "da"; 40 -> "ta"; else -> "de" }
        return when (n % 10) { 3, 4, 5 -> "te"; 6, 9 -> "da"; else -> "de" }
    }

    /** "14:36'da açılır"; baska gunse "Cum 14:36'da açılır"; gecmisse null. */
    fun resetText(epochSec: Long?, nowSec: Long, zone: ZoneId = ZoneId.systemDefault()): String? {
        if (epochSec == null || epochSec < nowSec) return null
        val t = Instant.ofEpochSecond(epochSec).atZone(zone)
        val hm = "%02d:%02d".format(t.hour, t.minute)
        // Okunus son sayiya gore: dakika 0 degilse dakika, degilse saat.
        val suf = suffix(if (t.minute != 0) t.minute else t.hour)
        val sameDay = t.toLocalDate() == Instant.ofEpochSecond(nowSec).atZone(zone).toLocalDate()
        val day = if (sameDay) "" else DAYS[t.dayOfWeek.value - 1] + " "
        return "$day$hm'$suf açılır"
    }

    private val DAYS = listOf("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")

    /** Uzun biçim: "33 dakika", "2 saat 10 dakika", "3 gün 4 saat" ve -da/-te/-de eki. */
    fun remainingLong(seconds: Long): String {
        if (seconds < 60) return "1 dakikadan az"
        val d = seconds / 86_400
        val h = seconds % 86_400 / 3_600
        val m = seconds % 3_600 / 60
        return when {
            d > 0 -> if (h > 0) "$d gün $h saat" else "$d gün"
            h > 0 -> if (m > 0) "$h saat $m dakika" else "$h saat"
            else -> "$m dakika"
        }
    }

    private fun tukenmeText(sec: Long): String {
        if (sec < 60) return "Bu hızla 1 dakikadan az sürede tükenir"
        val text = remainingLong(sec)
        val suf = when (text.substringAfterLast(' ')) { "dakika" -> "da"; "saat" -> "te"; else -> "de" }
        return "Bu hızla $text$suf tükenir"
    }

    /** Sifirlanmaya kalan sure ("3 sa 50 dk", "6 g 17 sa"); gecmis ya da yoksa null. */
    fun untilReset(epochSec: Long?, nowSec: Long): String? =
        if (epochSec == null || epochSec <= nowSec) null else remaining(epochSec - nowSec)

    /** Tempo rozeti: on yuzde %100 ise "Doldu", tukenme varsa en yakini; yoksa null. */
    fun tempo(p: AiProvider): String? {
        val front = frontLimits(p.limitler)
        if (front.any { it.yuzde >= 100 }) return "Doldu"
        return front.mapNotNull { it.tukenme }.filter { it > 0 }.minOrNull()?.let { tukenmeText(it) }
    }

    /** Kart basligi: "Claude" ya da hesap varsa "Claude · İş". */
    fun title(p: AiProvider): String = if (p.hesap.isNullOrBlank()) p.ad else p.ad + " · " + p.hesap

    /** Rozet yoksa saglayici notu. */
    fun note(p: AiProvider): String? = tempo(p) ?: p.notu
}
