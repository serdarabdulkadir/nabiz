package com.nabiz.android.alerts

import com.nabiz.android.peer.Snapshot
import java.util.Locale

/** Kuralin konusu: bildirimin hangi cihazin verisi icin atildigi. */
enum class Subject(val key: String) { MAC("mac"), TELEFON("telefon") }

data class RuleConfig(val on: Boolean, val esik: Int, val sureDk: Int)

/** docs/uyarilar.md kural tablosu. */
enum class AlertRule(val id: String, val ad: String, val subjects: Set<Subject>) {
    PIL_DUSUK("pil_dusuk", "Pil azaldı", setOf(Subject.MAC, Subject.TELEFON)),
    PIL_DOLDU("pil_doldu", "Şarj doldu", setOf(Subject.MAC, Subject.TELEFON)),
    DISK_DOLU("disk_dolu", "Depolama doluyor", setOf(Subject.MAC, Subject.TELEFON)),
    CPU_YUKSEK("cpu_yuksek", "İşlemci yüksek", setOf(Subject.MAC)),
    BELLEK_KRITIK("bellek_kritik", "Bellek baskısı", setOf(Subject.MAC)),
    SICAK("sicak", "Cihaz ısındı", setOf(Subject.MAC, Subject.TELEFON)),
    BAGLANTI_KOPTU("baglanti_koptu", "Bağlantı koptu", setOf(Subject.MAC));

    /** Esik kaydirici araligi; null: esiksiz. */
    fun esikRange(s: Subject): IntRange? = when (this) {
        PIL_DUSUK -> 5..50
        PIL_DOLDU -> 80..100
        DISK_DOLU -> 70..99
        CPU_YUKSEK -> 50..100
        SICAK -> if (s == Subject.TELEFON) 35..50 else null
        BELLEK_KRITIK, BAGLANTI_KOPTU -> null
    }

    /** Sure (dk) araligi; null: sure yok. */
    val sureRange: IntRange? get() = when (this) {
        CPU_YUKSEK -> 1..15
        BAGLANTI_KOPTU -> 2..60
        else -> null
    }

    fun defaults(s: Subject): RuleConfig = when (this) {
        PIL_DUSUK -> RuleConfig(true, 20, 0)
        PIL_DOLDU -> RuleConfig(false, 100, 0)
        DISK_DOLU -> RuleConfig(true, 90, 0)
        CPU_YUKSEK -> RuleConfig(false, 90, 2)
        BELLEK_KRITIK -> RuleConfig(false, 0, 0)
        SICAK -> RuleConfig(s == Subject.TELEFON, if (s == Subject.TELEFON) 42 else 0, 0)
        BAGLANTI_KOPTU -> RuleConfig(false, 0, 10)
    }

    /** Ayarlar satirinin gri aciklamasi. */
    fun describe(s: Subject, c: RuleConfig): String = when (this) {
        PIL_DUSUK -> "%${c.esik} ve altı, şarjda değilken"
        PIL_DOLDU -> "%${c.esik} ve üstü, şarjdayken"
        DISK_DOLU -> "%${c.esik} ve üstü dolu"
        CPU_YUKSEK -> "%${c.esik} ve üstü, ${c.sureDk} dk boyunca"
        BELLEK_KRITIK -> "Bellek baskısı kritik olunca"
        SICAK -> if (s == Subject.TELEFON) "${c.esik}°C ve üstü" else "Isı durumu kritik olunca"
        BAGLANTI_KOPTU -> "${c.sureDk} dk görülmedi"
    }
}

data class AlertFire(val rule: AlertRule, val subject: Subject, val title: String, val text: String)

/** Kalici durum (docs: .son ve .aktif anahtarlari). */
interface AlertState {
    fun son(rule: AlertRule, s: Subject): Long
    fun setSon(rule: AlertRule, s: Subject, epochSec: Long)
    fun aktif(rule: AlertRule, s: Subject): Boolean
    fun setAktif(rule: AlertRule, s: Subject, v: Boolean)
}

/**
 * Saf kural motoru: zaman disaridan verilir. Kosul yanlistan dogruya gecince bir kez atar;
 * histerezisle kapanmadan tekrar atmaz; ayni ornek 30 dk'dan sik atmaz.
 * Surecte ilk degerlendirmede kosul zaten dogruysa atilir (soguma yine gecerli).
 */
class AlertEngine(
    private val config: (AlertRule, Subject) -> RuleConfig,
    private val state: AlertState,
) {
    private val seen = HashSet<String>()
    private val since = HashMap<String, Long>()
    private val lastEval = HashMap<Subject, Long>()

    private class Reading(val cond: Boolean, val clear: Boolean, val text: String)

    /** Snapshot tabanli kurallar. [sampleAtMs]: verinin alindigi an (telefon icin now). */
    fun evaluate(subject: Subject, snap: Snapshot?, nowMs: Long, sampleAtMs: Long, device: String): List<AlertFire> {
        val last = lastEval[subject]
        if (last != null && nowMs - last > STALE_MS) clearSince(subject)
        lastEval[subject] = nowMs
        if (snap == null || nowMs - sampleAtMs > STALE_MS) { clearSince(subject); return emptyList() }
        val out = ArrayList<AlertFire>()
        for (rule in AlertRule.entries) {
            if (rule == AlertRule.BAGLANTI_KOPTU || subject !in rule.subjects) continue
            val cfg = config(rule, subject)
            step(rule, subject, cfg, read(rule, subject, cfg, snap), nowMs, device)?.let { out += it }
        }
        return out
    }

    /** baglanti_koptu: yalniz karsi cihaz (Mac). [lastSeenMs] 0 ise hic gorulmedi. */
    fun evaluateLink(nowMs: Long, lastSeenMs: Long, ready: Boolean, sleeping: Boolean, device: String): List<AlertFire> {
        val rule = AlertRule.BAGLANTI_KOPTU
        val cfg = config(rule, Subject.MAC)
        val cond = !ready && !sleeping && lastSeenMs > 0 && nowMs - lastSeenMs >= cfg.sureDk * 60_000L
        val min = ((nowMs - lastSeenMs) / 60_000L).coerceAtLeast(cfg.sureDk.toLong())
        val r = Reading(cond, !cond, "$min dakikadır görülmedi.")
        return listOfNotNull(step(rule, Subject.MAC, cfg, r, nowMs, device))
    }

    private fun read(rule: AlertRule, s: Subject, c: RuleConfig, snap: Snapshot): Reading? {
        val b = snap.battery
        return when (rule) {
            AlertRule.PIL_DUSUK -> b?.let {
                Reading(it.level <= c.esik && !it.charging, it.level >= c.esik + 5 || it.charging, "%${it.level} kaldı, şarjda değil.")
            }
            AlertRule.PIL_DOLDU -> b?.let {
                val cond = it.level >= c.esik && it.charging
                Reading(cond, !cond, "%${it.level} doldu.")
            }
            AlertRule.DISK_DOLU -> snap.disk?.takeIf { it.total > 0 }?.let {
                val pct = it.used * 100.0 / it.total
                val free = Math.round((it.total - it.used) / 1e9)
                Reading(pct >= c.esik, pct < c.esik - 2, "Disk %${pct.toInt()} dolu, $free GB boş.")
            }
            AlertRule.CPU_YUKSEK -> snap.cpu?.let {
                Reading(it.total >= c.esik, it.total < c.esik - 10, "İşlemci ${c.sureDk} dakikadır %${it.total}.")
            }
            AlertRule.BELLEK_KRITIK -> snap.mem?.pressure?.let {
                val cond = it == "critical"
                Reading(cond, !cond, "Bellek baskısı kritik.")
            }
            AlertRule.SICAK ->
                if (s == Subject.TELEFON) b?.temp?.let {
                    Reading(it >= c.esik, it < c.esik - 2, "Pil ${String.format(Locale("tr"), "%.1f", it)}°C.")
                } else snap.thermal?.let {
                    val cond = it == "critical"
                    Reading(cond, !cond, "Isı durumu kritik.")
                }
            AlertRule.BAGLANTI_KOPTU -> null
        }
    }

    private fun step(rule: AlertRule, s: Subject, cfg: RuleConfig, r: Reading?, nowMs: Long, device: String): AlertFire? {
        val key = "${rule.id}.${s.key}"
        if (!cfg.on) {
            if (state.aktif(rule, s)) state.setAktif(rule, s, false)
            since.remove(key)
            return null
        }
        if (r == null) return null
        var aktif = if (seen.add(key)) false else state.aktif(rule, s)
        if (r.cond) since.getOrPut(key) { nowMs } else since.remove(key)
        if (aktif) {
            if (r.clear) state.setAktif(rule, s, false) else state.setAktif(rule, s, true)
            return null
        }
        val sureMs = if (rule == AlertRule.CPU_YUKSEK) cfg.sureDk * 60_000L else 0L
        val start = since[key]
        if (!r.cond || start == null || nowMs - start < sureMs) {
            state.setAktif(rule, s, false)
            return null
        }
        aktif = true
        state.setAktif(rule, s, aktif)
        val nowSec = nowMs / 1000
        if (nowSec - state.son(rule, s) < COOLDOWN_SEC) return null
        state.setSon(rule, s, nowSec)
        return AlertFire(rule, s, "$device: ${rule.ad}", r.text)
    }

    private fun clearSince(s: Subject) { since.keys.removeAll { it.endsWith("." + s.key) } }

    companion object {
        const val STALE_MS = 2 * 60_000L
        const val COOLDOWN_SEC = 30 * 60L
    }
}
