package com.nabiz.android.stats

/** Saf olcum mantigi (Android'e bagimli degil, JVM birim testli). */
object StatsMath {
    /** `lowMemory` bayragi kritik; bos bellek %15 altindaysa uyari. */
    fun memPressure(avail: Long, total: Long, lowMemory: Boolean): String = when {
        lowMemory -> "critical"
        total > 0 && avail * 100 < total * 15 -> "warn"
        else -> "normal"
    }

    /** android.os.PowerManager.THERMAL_STATUS_*: 0 yok, 1 hafif, 2 orta, 3 agir, 4 kritik, 5 acil, 6 kapanma. */
    fun thermal(status: Int): String? = when (status) {
        0, 1 -> "normal"
        2 -> "warn"
        in 3..6 -> "critical"
        else -> null
    }

    /** Sayac farkindan bayt/sn. Sayac okunamazsa (-1) ya da geriye giderse (yeniden baslama) null. */
    fun rate(prev: Long, now: Long, elapsedMs: Long): Long? {
        if (prev < 0 || now < 0 || now < prev || elapsedMs <= 0) return null
        return (now - prev) * 1000 / elapsedMs
    }

    /** Pil yuzdesi: level/scale; okunamazsa null. */
    fun batteryPercent(level: Int, scale: Int): Int? {
        if (level < 0 || scale <= 0) return null
        return (level * 100 / scale).coerceIn(0, 100)
    }

    /** BatteryManager sicakligi onda bir santigrat verir. */
    fun tempC(tenths: Int): Double? = if (tenths == Int.MIN_VALUE || tenths <= -1000) null else tenths / 10.0
}
