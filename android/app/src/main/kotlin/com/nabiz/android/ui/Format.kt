package com.nabiz.android.ui

import java.util.Locale

/** Gosterim bicimleri (saf, JVM birim testli). Okunamayan deger `--`. */
object Format {
    const val NONE = "--"

    fun percent(used: Long, total: Long): Int? = if (total <= 0) null else (used * 100 / total).toInt().coerceIn(0, 100)

    fun bytes(b: Long): String {
        val gb = b / 1_073_741_824.0
        return if (gb >= 1) String.format(Locale.US, "%.1f GB", gb) else String.format(Locale.US, "%.0f MB", b / 1_048_576.0)
    }

    /** Dosya boyutu: kucuk dosyalar da gorunsun diye KB/B dahil. */
    fun size(b: Long): String = when {
        b >= 1_073_741_824 -> String.format(Locale.US, "%.1f GB", b / 1_073_741_824.0)
        b >= 1_048_576 -> String.format(Locale.US, "%.1f MB", b / 1_048_576.0)
        b >= 1024 -> String.format(Locale.US, "%.0f KB", b / 1024.0)
        else -> "$b B"
    }

    fun rate(bps: Long): String = when {
        bps >= 1_048_576 -> String.format(Locale.US, "%.1f MB/s", bps / 1_048_576.0)
        bps >= 1024 -> String.format(Locale.US, "%.0f KB/s", bps / 1024.0)
        else -> "$bps B/s"
    }

    fun uptime(sec: Long): String {
        val d = sec / 86_400
        val h = sec % 86_400 / 3600
        val m = sec % 3600 / 60
        return when {
            d > 0 -> "${d}g ${h}sa"
            h > 0 -> "${h}sa ${m}dk"
            else -> "${m}dk"
        }
    }

    /** Saat:dakika (yerel). */
    fun clock(ms: Long): String = java.text.SimpleDateFormat("HH:mm", Locale.getDefault()).format(java.util.Date(ms))

    fun temp(c: Double): String = String.format(Locale.US, "%.1f°C", c)
}
