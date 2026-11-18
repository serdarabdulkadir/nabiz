package com.nabiz.android.service

import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkReason
import com.nabiz.android.peer.LinkState
import com.nabiz.android.peer.Snapshot
import com.nabiz.android.ui.Format

enum class Tone { NORMAL, WARN, CRIT, GOOD, TRACK }

/** Ilerleme cubugu dilimi (uzunluk, renk tonu). */
data class Seg(val length: Int, val tone: Tone)

/** Esik noktasi (ilerleme cubugunda ince isaret). */
data class Pt(val at: Int, val tone: Tone)

data class CardAction(val eylem: String, val label: String)

/** Mac kartinin (kalici bildirim) icerigi. Saf mantik; esitlik karsilastirmasi degisim denetimi icindir. */
data class MacCardModel(
    val title: String,
    val text: String,
    /** Acilinca gorunen cok satirli metin (yalniz Ayrintili). */
    val bigText: String?,
    /** ProgressStyle ilerlemesi (0..progressMax); null = cubuk yok. */
    val progress: Int?,
    val progressMax: Int,
    val segments: List<Seg>,
    /** API<36 yedegi icin 0..100 ilerleme. */
    val compatProgress: Int?,
    val shortCritical: String?,
    val actions: List<CardAction>,
    val charging: Boolean = false,
    val style: NotifStyle = NotifStyle.CANLI,
    val points: List<Pt> = emptyList(),
    /** Bildirim alt metni: baglanti yolu. */
    val subText: String? = null,
) {
    val showActions: Boolean get() = actions.isNotEmpty()

    companion object {
        const val NORMAL_MAX = 75
        const val WARN_MAX = 90
        private val NONE = Format.NONE

        private val LABELS = mapOf("yenile" to "Yenile", "kilitle" to "Kilitle", "uyut" to "Uyut", "uyandir" to "Uyandır")

        /** Mac'in durumuna gore dugmeler (en cok 3). Kilitliyse Kilitle yok; ekran kapaliysa Uyandir; Uyut yalniz uyanikken. */
        fun actionsFor(state: LinkState): List<CardAction> {
            if (state.phase != LinkPhase.READY) return emptyList()
            val ms = state.macState
            val keys = when {
                ms == null -> listOf("yenile", "kilitle", "uyut")
                ms.uykuyaGidiyor -> emptyList()
                ms.ekranKapali -> listOf("yenile", "uyandir", "uyut")
                ms.kilitli -> listOf("yenile", "uyut")
                else -> listOf("yenile", "kilitle", "uyut")
            }
            return keys.map { CardAction(it, LABELS.getValue(it)) }
        }

        /** Cip metni (<=7 karakter): en agir esik asimindaki metrik; hicbiri esik asmiyorsa CPU. */
        fun criticalChip(cpu: Int?, ram: Int?, disk: Int?): String? {
            val items = listOf(Triple("CPU", cpu, NORMAL_MAX to WARN_MAX), Triple("RAM", ram, 75 to 90), Triple("DSK", disk, 75 to 90))
            fun sev(v: Int, th: Pair<Int, Int>) = if (v >= th.second) 2 else if (v >= th.first) 1 else 0
            val worst = items.filter { it.second != null }
                .maxWithOrNull(compareBy<Triple<String, Int?, Pair<Int, Int>>> { sev(it.second!!, it.third) }.thenBy { if (it.first == "CPU") 1 else 0 }.thenBy { it.second })
                ?: return null
            return "${worst.first} ${worst.second}"
        }

        fun sleepingText(lastSeenAt: Long, timeFmt: (Long) -> String = Format::clock): String =
            "Mac uykuda" + if (lastSeenAt > 0) " · son görülme ${timeFmt(lastSeenAt)}" else ""

        fun from(
            state: LinkState,
            style: NotifStyle = NotifStyle.CANLI,
            nameFallback: String = "Mac",
            timeFmt: (Long) -> String = Format::clock,
        ): MacCardModel {
            if (state.phase != LinkPhase.READY) {
                if (state.reason == LinkReason.SLEEPING) {
                    return plain(state.macName ?: "Nabız", sleepingText(state.lastSeenAt, timeFmt), "Uykuda")
                }
                val msg = if (state.phase == LinkPhase.AWAIT_SAS) "Eşleşme kodu onayı bekleniyor" else "Mac aranıyor…"
                return plain("Nabız", msg)
            }
            val s = state.macSnap
            val name = state.macName ?: nameFallback
            val lock = if (state.macState?.kilitli == true) " · Kilitli" else ""
            val pil = s?.battery?.level
            val charging = s?.battery?.charging == true
            val cpu = s?.cpu?.total?.coerceIn(0, 100)
            val actions = actionsFor(state)
            val ramV = s?.mem?.let { pctOrNull(it.used, it.total) }
            val diskV = s?.disk?.let { pctOrNull(it.used, it.total) }
            val short = criticalChip(cpu, ramV, diskV)
            val sub = (if (state.via == com.nabiz.android.peer.LinkVia.REMOTE) "Uzak (Tailscale)" else "Yerel ağ") + (state.rttMs?.let { " · $it ms" } ?: "")
            val canliTitle = (if (pil != null) "$name · %$pil" else name) + lock
            return when (style) {
                NotifStyle.CANLI -> MacCardModel(
                    canliTitle, text(s), null, cpu, 100,
                    listOf(Seg(NORMAL_MAX, Tone.NORMAL), Seg(WARN_MAX - NORMAL_MAX, Tone.WARN), Seg(100 - WARN_MAX, Tone.CRIT)),
                    cpu, short, actions, charging, style,
                    listOf(Pt(NORMAL_MAX, Tone.WARN), Pt(WARN_MAX, Tone.CRIT)), sub,
                )
                NotifStyle.UCLU -> {
                    val vals = listOf(
                        cpu to (NORMAL_MAX to WARN_MAX),
                        s?.mem?.let { pctOrNull(it.used, it.total) } to (75 to 90),
                        s?.disk?.let { pctOrNull(it.used, it.total) } to (75 to 90),
                    )
                    val segs = ArrayList<Seg>()
                    for ((v, th) in vals) {
                        if (v == null) { segs += Seg(100, Tone.TRACK); continue }
                        val tone = if (v >= th.second) Tone.CRIT else if (v >= th.first) Tone.WARN else Tone.NORMAL
                        if (v > 0) segs += Seg(v, tone)
                        if (v < 100) segs += Seg(100 - v, Tone.TRACK)
                    }
                    val txt = "CPU ${cpu ?: NONE} · RAM ${vals[1].first ?: NONE} · Disk ${vals[2].first ?: NONE}"
                    MacCardModel(
                        canliTitle, txt, null, 300, 300, segs,
                        vals.mapNotNull { it.first }.maxOrNull(), short, actions, charging, style,
                        listOf(Pt(100, Tone.TRACK), Pt(200, Tone.TRACK)), sub,
                    )
                }
                NotifStyle.KOMPAKT -> {
                    val ram = s?.mem?.let { pct(it.used, it.total) } ?: NONE
                    val t = "$name · " + (if (pil != null) "%$pil pil" else "pil $NONE") + lock
                    MacCardModel(t, "CPU ${cpu?.let { "$it%" } ?: NONE} · RAM $ram", null, null, 100, emptyList(), null, short, actions, charging, style)
                }
                NotifStyle.AYRINTILI -> MacCardModel(
                    canliTitle, text(s), detailLines(s, state), null, 100, emptyList(), null, short, actions, charging, style, emptyList(), sub,
                )
                NotifStyle.PIL -> {
                    val b = s?.battery
                    val title = "$name · " + (b?.let { "%${it.level}" } ?: NONE) + (if (b?.charging == true) " · Şarjda" else "") + lock
                    val rest = b?.minutes?.let { Format.uptime(it * 60L) } ?: NONE
                    val txt = if (b == null) "Pil bilgisi $NONE" else if (b.charging) "Şarj oluyor · dolmasına $rest" else "Pilde · kalan $rest"
                    val tone = when {
                        b == null -> Tone.TRACK
                        b.charging -> Tone.GOOD
                        b.level <= 20 -> Tone.CRIT
                        b.level <= 40 -> Tone.WARN
                        else -> Tone.NORMAL
                    }
                    val lvl = b?.level?.coerceIn(0, 100)
                    val segs = when {
                        lvl == null -> listOf(Seg(100, Tone.TRACK))
                        lvl >= 100 -> listOf(Seg(100, tone))
                        lvl <= 0 -> listOf(Seg(100, Tone.TRACK))
                        else -> listOf(Seg(lvl, tone), Seg(100 - lvl, Tone.TRACK))
                    }
                    MacCardModel(
                        title, txt, null, lvl, 100, segs,
                        lvl, lvl?.let { "%$it" }, actions, b?.charging == true, style, emptyList(), sub,
                    )
                }
            }
        }

        private fun plain(title: String, msg: String, short: String? = null) =
            MacCardModel(title, msg, null, null, 100, emptyList(), null, short, emptyList())

        fun detailLines(s: Snapshot?, state: LinkState): String {
            val lines = ArrayList<String>()
            lines += "CPU " + (s?.cpu?.total?.let { "$it%" } ?: NONE)
            lines += "GPU " + (s?.gpu?.let { "$it%" } ?: NONE)
            lines += "RAM " + (s?.mem?.let { pct(it.used, it.total) + " · " + Format.bytes(it.used) + " / " + Format.bytes(it.total) } ?: NONE)
            lines += "Disk " + (s?.disk?.let { pct(it.used, it.total) + " · " + Format.bytes(it.used) + " / " + Format.bytes(it.total) } ?: NONE)
            val b = s?.battery
            lines += "Pil " + (b?.let {
                "%${it.level} · " + (if (it.charging) "şarj oluyor" else "pilde") + (it.minutes?.let { m -> " · " + Format.uptime(m * 60L) } ?: "")
            } ?: NONE)
            lines += "Ağ " + (s?.net?.let { "↓ " + Format.rate(it.down) + " ↑ " + Format.rate(it.up) } ?: NONE)
            lines += "Çalışma süresi " + (s?.uptime?.let { Format.uptime(it) } ?: NONE)
            lines += "Kilit " + (state.macState?.let { if (it.kilitli) "kilitli" else "açık" } ?: NONE)
            return lines.joinToString("\n")
        }

        fun text(s: Snapshot?): String {
            val cpu = s?.cpu?.total?.let { "$it%" } ?: "--"
            val ram = s?.mem?.let { pct(it.used, it.total) } ?: "--"
            val disk = s?.disk?.let { pct(it.used, it.total) } ?: "--"
            return "CPU $cpu · RAM $ram · Disk $disk"
        }

        private fun pctOrNull(used: Long, total: Long): Int? =
            if (total <= 0) null else (used * 100 / total).toInt().coerceIn(0, 100)

        private fun pct(used: Long, total: Long): String = pctOrNull(used, total)?.let { "$it%" } ?: "--"
    }
}
