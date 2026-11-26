package com.nabiz.android.aktar

import com.nabiz.android.peer.AktarFile
import com.nabiz.android.ui.Format

// Aktar gosterim modeli (saf Kotlin, JVM testli).

enum class TransferDir { OUT, IN }

enum class TransferStatus {
    /** Gelen teklif, kullanici Kabul et / Reddet bekleniyor. */
    OFFERED,
    /** Giden teklif, Mac yaniti bekleniyor. */
    WAITING,
    CONNECTING,
    ACTIVE,
    DONE,
    FAILED,
    REJECTED,
    CANCELLED,
}

data class TransferInfo(
    val aid: String,
    val dir: TransferDir,
    val peer: String,
    val files: List<AktarFile>,
    val status: TransferStatus,
    val doneBytes: Long = 0L,
    val speedBps: Long = 0L,
    val detail: String? = null,
    val startedAt: Long = 0L,
    val endedAt: Long = 0L,
) {
    val totalBytes: Long get() = files.sumOf { it.boyut }
    val running: Boolean get() = status == TransferStatus.WAITING || status == TransferStatus.CONNECTING || status == TransferStatus.ACTIVE
    val title: String get() = if (files.size == 1) files[0].ad else "${files.size} dosya"
    /** 0..100. */
    val percent: Int get() = if (totalBytes <= 0) (if (status == TransferStatus.DONE) 100 else 0) else (doneBytes * 100 / totalBytes).toInt().coerceIn(0, 100)
}

object AktarText {
    /** "<Mac adi> N dosya gondermek istiyor". */
    fun offerTitle(peer: String, count: Int): String = "$peer $count dosya göndermek istiyor"

    fun offerBody(files: List<AktarFile>): String {
        val names = files.take(3).joinToString(", ") { it.ad } + if (files.size > 3) " ve ${files.size - 3} dosya daha" else ""
        return names + " · " + Format.size(files.sumOf { it.boyut })
    }

    fun statusLabel(s: TransferStatus): String = when (s) {
        TransferStatus.OFFERED -> "Onay bekliyor"
        TransferStatus.WAITING -> "Yanıt bekleniyor"
        TransferStatus.CONNECTING -> "Bağlanıyor"
        TransferStatus.ACTIVE -> "Sürüyor"
        TransferStatus.DONE -> "Bitti"
        TransferStatus.FAILED -> "Başarısız"
        TransferStatus.REJECTED -> "Reddedildi"
        TransferStatus.CANCELLED -> "İptal edildi"
    }

    /** Paylas sayfasi: "N öğe paylaş" ve "Orijinal kalite · boyut". */
    fun shareTitle(count: Int): String = "$count öğe paylaş"
    fun shareSub(totalBytes: Long?): String = "Orijinal kalite" + (totalBytes?.takeIf { it > 0 }?.let { " · " + Format.size(it) } ?: "")

    /** Ilerleme bildirimi basligi. */
    fun progressTitle(t: TransferInfo): String =
        if (t.dir == TransferDir.OUT) "${t.title} ${t.peer}'e gönderiliyor" else "${t.title} alınıyor"

    /** Sonuc bildirimi basligi. */
    fun resultTitle(t: TransferInfo): String = when (t.status) {
        TransferStatus.DONE -> if (t.dir == TransferDir.OUT) "${t.title} gönderildi" else "${t.title} alındı"
        TransferStatus.FAILED -> "${t.title} aktarılamadı"
        else -> t.title + " · " + statusLabel(t.status)
    }

    fun rejectReason(neden: String?): String = when (neden) {
        "kapali" -> "Mac'te Aktar kapalı"
        "yer_yok" -> "Mac'te yeterli yer yok"
        else -> "Mac reddetti"
    }

    /** Liste satiri alt metni: yon oku, es adi, boyut, hiz. */
    fun subtitle(t: TransferInfo): String {
        val arrow = if (t.dir == TransferDir.OUT) "↑" else "↓"
        val sb = StringBuilder("$arrow ${t.peer}")
        when (t.status) {
            TransferStatus.ACTIVE, TransferStatus.CONNECTING -> {
                sb.append(" · ").append(Format.size(t.doneBytes)).append(" / ").append(Format.size(t.totalBytes))
                if (t.status == TransferStatus.ACTIVE && t.speedBps > 0) sb.append(" · ").append(Format.rate(t.speedBps))
            }
            else -> sb.append(" · ").append(Format.size(t.totalBytes))
        }
        t.detail?.let { sb.append(" · ").append(it) }
        return sb.toString()
    }
}

/** Hiz olcer: en az 500 ms araliklarla ornekler, ussel ortalama (yumusatma). */
class SpeedMeter {
    private var lastAt = 0L
    private var lastBytes = 0L
    private var speed = 0.0

    /** `nowMs`: monoton ms; `bytes`: toplam ilerleme. Donen: bayt/sn. */
    fun update(nowMs: Long, bytes: Long): Long {
        if (lastAt == 0L) { lastAt = nowMs; lastBytes = bytes; return 0L }
        val dt = nowMs - lastAt
        if (dt < 500) return speed.toLong()
        val inst = (bytes - lastBytes).coerceAtLeast(0) * 1000.0 / dt
        speed = if (speed == 0.0) inst else speed * 0.6 + inst * 0.4
        lastAt = nowMs; lastBytes = bytes
        return speed.toLong()
    }
}
