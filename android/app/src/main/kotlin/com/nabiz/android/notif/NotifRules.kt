package com.nabiz.android.notif

import com.nabiz.android.peer.PhoneNotif

/** Android sinifindan bagimsiz ara veri: StatusBarNotification'dan NotifHub doldurur, kurallar bunun uzerinde calisir. */
data class RawNotif(
    val key: String,
    val packageName: String,
    val appName: String,
    val title: String?,
    val text: String?,
    val postTimeMs: Long,
    val ongoing: Boolean,
    val groupSummary: Boolean,
    val category: String?,
    val replyable: Boolean,
    val clearable: Boolean,
)

/** Mac'e hangi bildirimlerin, hangi bicimde gidecegi (docs/protokol.md bolum 10). */
object NotifRules {
    const val MAX_TEXT = 400
    const val MAX_LIST = 50
    const val MAX_TITLE = 200
    const val MAX_APP = 200
    /** notif.list JSON'u icin yaklasik ust sinir (cerceve siniri 1 MiB). */
    const val LIST_BUDGET_CHARS = 900_000
    const val MAX_ICON_BASE64 = 6 * 1024
    // Notification.CATEGORY_CALL / CATEGORY_TRANSPORT degerleri.
    const val CATEGORY_CALL = "call"
    const val CATEGORY_TRANSPORT = "transport"

    fun accept(n: RawNotif, ownPackage: String): Boolean =
        n.packageName != ownPackage &&
            !n.ongoing &&
            !n.groupSummary &&
            n.category != CATEGORY_CALL &&
            n.category != CATEGORY_TRANSPORT &&
            !(n.title.isNullOrBlank() && n.text.isNullOrBlank())

    /** En cok [MAX_TEXT] karakter; vekil cift ortasindan kesilmez. */
    fun truncate(text: String, max: Int = MAX_TEXT): String {
        if (text.length <= max) return text
        var end = max
        if (Character.isHighSurrogate(text[end - 1])) end--
        return text.substring(0, end)
    }

    private fun weight(n: PhoneNotif): Int =
        300 + n.anahtar.length + n.paket.length + n.uygulama.length * 2 + (n.baslik?.length ?: 0) * 2 +
            (n.metin?.length ?: 0) * 2 + (n.ikon?.length ?: 0)

    /** Liste butceye sigmazsa once ikonlar atilir, yine sigmazsa sondan (en eski) kirpilir. */
    fun fit(items: List<PhoneNotif>, budget: Int = LIST_BUDGET_CHARS): List<PhoneNotif> {
        if (items.sumOf { weight(it) } <= budget) return items
        val noIcons = items.map { it.copy(ikon = null) }
        var used = 0
        val out = ArrayList<PhoneNotif>()
        for (n in noIcons) {
            val w = weight(n)
            if (used + w > budget) break
            used += w; out += n
        }
        return out
    }

    fun toItem(n: RawNotif, icon: String?): PhoneNotif = PhoneNotif(
        anahtar = n.key,
        paket = n.packageName,
        uygulama = truncate(n.appName, MAX_APP),
        baslik = n.title?.takeIf { it.isNotBlank() }?.let { truncate(it, MAX_TITLE) },
        metin = n.text?.takeIf { it.isNotBlank() }?.let { truncate(it) },
        zaman = n.postTimeMs / 1000,
        yanitlanabilir = n.replyable,
        kapatilabilir = n.clearable,
        ikon = icon?.takeIf { it.length <= MAX_ICON_BASE64 },
    )

    /** Kabul edilenler, en yeni once, en cok [MAX_LIST]. */
    fun select(all: List<RawNotif>, ownPackage: String): List<RawNotif> =
        all.filter { accept(it, ownPackage) }.sortedByDescending { it.postTimeMs }.take(MAX_LIST)
}

/**
 * Ayni anahtar saniyede 1'den sik gonderilmez; araya giren guncellemeler tek "son hal" gonderimine indirilir.
 * Saf mantik: zamani cagiran verir, zamanlamayi (gecikme) cagiran yapar.
 */
class NotifThrottle(private val minGapMs: Long = 1000) {
    private val lastSent = HashMap<String, Long>()
    private val pending = HashSet<String>()

    /** 0: simdi gonder. >0: bu kadar ms sonra [fire] cagrilmali. -1: zaten bekleyen gonderim var (son hal onda gider). */
    @Synchronized
    fun offer(key: String, now: Long): Long {
        if (key in pending) return -1
        val last = lastSent[key]
        if (last == null || now - last >= minGapMs) { lastSent[key] = now; return 0 }
        pending += key
        return (last + minGapMs - now).coerceAtLeast(1)
    }

    /** Bekleyen gonderim zamani geldi. */
    @Synchronized
    fun fire(key: String, now: Long) {
        pending -= key
        lastSent[key] = now
    }

    @Synchronized
    fun forget(key: String) { pending -= key; lastSent.remove(key) }

    @Synchronized
    fun clear() { pending.clear(); lastSent.clear() }
}
