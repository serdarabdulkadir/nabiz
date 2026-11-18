package com.nabiz.android.phone

import com.nabiz.android.peer.PeerMessage

/** durum: bosta / caliyor / acik / araniyor. yon: gelen / giden. `startedAt` elapsedRealtime (ms). */
data class CallInfo(
    val durum: String = "bosta",
    val yon: String? = null,
    val numara: String? = null,
    val kisiAdi: String? = null,
    val startedAt: Long? = null,
) {
    /** call.state: bostayken yon yok; `sureSn` yalniz `acik`ta (Mac sayaci kendisi yurutur). */
    fun toMessage(nowElapsedMs: Long): PeerMessage.CallState =
        if (durum == "bosta") PeerMessage.CallState("bosta")
        else PeerMessage.CallState(
            durum, yon, numara, kisiAdi,
            if (durum == "acik") startedAt?.let { ((nowElapsedMs - it) / 1000).toInt().coerceAtLeast(0) } else null,
        )
}

enum class ActionResult { OK, NO_PERMISSION, UNSUPPORTED, INVALID, FAILED }

/** Aranabilir numara metni: bosluk, tire, parantez atilir; yalniz 0-9 + * # kalir. Gecersizse null. */
fun normalizeDialNumber(raw: String): String? {
    val s = raw.filterNot { it == ' ' || it == '-' || it == '(' || it == ')' || it == '.' }
    if (s.isEmpty() || s.length > 32) return null
    return if (s.all { it.isDigit() || it == '+' || it == '*' || it == '#' }) s else null
}
