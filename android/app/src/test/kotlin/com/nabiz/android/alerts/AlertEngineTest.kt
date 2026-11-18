package com.nabiz.android.alerts

import com.nabiz.android.peer.BatteryStats
import com.nabiz.android.peer.CpuStats
import com.nabiz.android.peer.DiskStats
import com.nabiz.android.peer.MemStats
import com.nabiz.android.peer.Snapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeState : AlertState {
    val son = HashMap<String, Long>(); val akt = HashMap<String, Boolean>()
    override fun son(rule: AlertRule, s: Subject) = son["${rule.id}${s.key}"] ?: 0L
    override fun setSon(rule: AlertRule, s: Subject, epochSec: Long) { son["${rule.id}${s.key}"] = epochSec }
    override fun aktif(rule: AlertRule, s: Subject) = akt["${rule.id}${s.key}"] ?: false
    override fun setAktif(rule: AlertRule, s: Subject, v: Boolean) { akt["${rule.id}${s.key}"] = v }
}

class AlertEngineTest {
    private val min = 60_000L
    private val state = FakeState()
    private var overrides = HashMap<String, RuleConfig>()
    private fun engine(state: AlertState = this.state) = AlertEngine({ r, s -> overrides["${r.id}${s.key}"] ?: r.defaults(s).copy(on = true) }, state)
    private fun bat(level: Int, ch: Boolean = false, temp: Double? = null) = Snapshot(ts = 0, battery = BatteryStats(level, ch, temp = temp))
    private fun eval(e: AlertEngine, s: Subject, snap: Snapshot, now: Long) = e.evaluate(s, snap, now, now, "Cihaz")
    private fun ids(l: List<AlertFire>) = l.map { it.rule }.toSet()

    @Test fun pilDusukFirstSampleFiresAndTextFormat() {
        val f = eval(engine(), Subject.TELEFON, bat(18), 10_000_000)
        assertEquals(setOf(AlertRule.PIL_DUSUK), ids(f))
        assertEquals("Cihaz: Pil azaldı", f[0].title); assertEquals("%18 kaldı, şarjda değil.", f[0].text)
    }

    @Test fun pilDusukHysteresisAndCooldown() {
        val e = engine(); var t = 10_000_000L
        assertEquals(1, eval(e, Subject.TELEFON, bat(18), t).size)
        t += 40 * min
        assertTrue(eval(e, Subject.TELEFON, bat(22), t).isEmpty())  // 20..24: kapanmadi
        assertTrue(eval(e, Subject.TELEFON, bat(19), t).isEmpty())  // hala aktif, tekrar atmaz
        assertTrue(eval(e, Subject.TELEFON, bat(25), t).isEmpty())  // kapandi
        assertEquals(1, eval(e, Subject.TELEFON, bat(19), t).size)  // yeniden doldu, soguma gecmis
    }

    @Test fun cooldownBlocksWithin30Min() {
        val e = engine(); var t = 10_000_000L
        assertEquals(1, eval(e, Subject.TELEFON, bat(18), t).size)
        eval(e, Subject.TELEFON, bat(30), t + min)
        assertTrue(eval(e, Subject.TELEFON, bat(18), t + 5 * min).isEmpty())
        eval(e, Subject.TELEFON, bat(30), t + 6 * min)
        assertEquals(1, eval(e, Subject.TELEFON, bat(18), t + 31 * min).size)
    }

    @Test fun pilDusukClosesOnCharging() {
        val e = engine(); val t = 10_000_000L
        eval(e, Subject.TELEFON, bat(18), t)
        assertTrue(eval(e, Subject.TELEFON, bat(18, true), t + 40 * min).isEmpty())
        assertEquals(1, eval(e, Subject.TELEFON, bat(18), t + 80 * min).size)
    }

    @Test fun pilDoldu() {
        overrides["pil_doldutelefon"] = RuleConfig(true, 100, 0)
        val e = engine()
        assertTrue(eval(e, Subject.TELEFON, bat(100, false), 5_000_000).isEmpty())
        assertEquals(setOf(AlertRule.PIL_DOLDU), ids(eval(e, Subject.TELEFON, bat(100, true), 5_000_000 + min)))
    }

    @Test fun diskDoluHysteresis() {
        val e = engine(); var t = 10_000_000L
        fun d(p: Long) = Snapshot(ts = 0, disk = DiskStats(p, 100_000_000_000))
        val f = eval(e, Subject.MAC, d(91_000_000_000), t)
        assertEquals("Disk %91 dolu, 9 GB boş.", f[0].text)
        t += 40 * min
        assertTrue(eval(e, Subject.MAC, d(89_000_000_000), t).isEmpty())  // 88..90: kapanmadi
        assertTrue(eval(e, Subject.MAC, d(91_000_000_000), t).isEmpty())
        eval(e, Subject.MAC, d(87_000_000_000), t)                          // < 88 kapandi
        assertEquals(1, eval(e, Subject.MAC, d(91_000_000_000), t).size)
    }

    @Test fun cpuNeedsDuration() {
        overrides["cpu_yuksekmac"] = RuleConfig(true, 90, 2)
        val e = engine(); val t = 10_000_000L
        fun c(v: Int) = Snapshot(ts = 0, cpu = CpuStats(v))
        assertTrue(eval(e, Subject.MAC, c(94), t).isEmpty())
        assertTrue(eval(e, Subject.MAC, c(94), t + min).isEmpty())
        val f = eval(e, Subject.MAC, c(94), t + 2 * min)
        assertEquals("İşlemci 2 dakikadır %94.", f[0].text)
        // kesinti: dusunce sayac sifirlanir
        val e2 = engine(FakeState())
        eval(e2, Subject.MAC, c(94), t); eval(e2, Subject.MAC, c(50), t + min)
        assertTrue(eval(e2, Subject.MAC, c(94), t + 2 * min).isEmpty())
        assertTrue(eval(e2, Subject.MAC, c(94), t + 3 * min).isEmpty())
        assertEquals(1, eval(e2, Subject.MAC, c(94), t + 4 * min).size)
    }

    @Test fun cpuHysteresis() {
        overrides["cpu_yuksekmac"] = RuleConfig(true, 90, 1)
        val e = engine(); var t = 10_000_000L
        fun c(v: Int) = Snapshot(ts = 0, cpu = CpuStats(v))
        eval(e, Subject.MAC, c(95), t); assertEquals(1, eval(e, Subject.MAC, c(95), t + min).size)
        t += 60 * min
        eval(e, Subject.MAC, c(85), t)               // 80..90: aktif kalir
        eval(e, Subject.MAC, c(95), t + min); assertTrue(eval(e, Subject.MAC, c(95), t + 2 * min).isEmpty())
        eval(e, Subject.MAC, c(70), t + 3 * min)     // < 80: kapandi
        eval(e, Subject.MAC, c(95), t + 4 * min); assertEquals(1, eval(e, Subject.MAC, c(95), t + 5 * min).size)
    }

    @Test fun cpuStaleGapResetsDuration() {
        overrides["cpu_yuksekmac"] = RuleConfig(true, 90, 2)
        val e = engine(); val t = 10_000_000L
        fun c() = Snapshot(ts = 0, cpu = CpuStats(95))
        eval(e, Subject.MAC, c(), t)
        assertTrue(eval(e, Subject.MAC, c(), t + 10 * min).isEmpty())  // kopukluktan sonra sayac yeniden
    }

    @Test fun bellekKritik() {
        overrides["bellek_kritikmac"] = RuleConfig(true, 0, 0)
        val e = engine()
        assertTrue(eval(e, Subject.MAC, Snapshot(ts = 0, mem = MemStats(1, 2, "warn")), 5_000_000).isEmpty())
        assertEquals(1, eval(e, Subject.MAC, Snapshot(ts = 0, mem = MemStats(1, 2, "critical")), 5_000_000 + min).size)
    }

    @Test fun sicakPhoneAndMac() {
        val e = engine(); var t = 10_000_000L
        val f = eval(e, Subject.TELEFON, bat(50, temp = 44.2), t)
        assertEquals("Pil 44,2°C.", f[0].text)
        t += 40 * min
        assertTrue(eval(e, Subject.TELEFON, bat(50, temp = 40.5), t).isEmpty())  // 40..42 kapanmadi
        eval(e, Subject.TELEFON, bat(50, temp = 39.0), t)
        assertEquals(1, eval(e, Subject.TELEFON, bat(50, temp = 43.0), t).size)
        assertEquals(1, eval(e, Subject.MAC, Snapshot(ts = 0, thermal = "critical"), t).size)
        assertTrue(eval(e, Subject.MAC, Snapshot(ts = 0, thermal = null), t).isEmpty())
    }

    @Test fun staleCounterpartDataIgnored() {
        val e = engine()
        val now = 10_000_000L
        assertTrue(e.evaluate(Subject.MAC, bat(10), now, now - 3 * min, "Mac").isEmpty())
        assertEquals(1, e.evaluate(Subject.MAC, bat(10), now, now - 1 * min, "Mac").size)
    }

    @Test fun disabledRuleIsSilent() {
        overrides["pil_dusuktelefon"] = RuleConfig(false, 20, 0)
        assertTrue(eval(engine(), Subject.TELEFON, bat(5), 5_000_000).isEmpty())
    }

    @Test fun firesOnFirstSampleAfterRestartEvenIfPersistedActive() {
        val st = FakeState(); st.setAktif(AlertRule.PIL_DUSUK, Subject.TELEFON, true)
        assertEquals(1, eval(engine(st), Subject.TELEFON, bat(10), 10_000_000).size)
    }

    @Test fun baglantiKoptu() {
        overrides["baglanti_koptumac"] = RuleConfig(true, 0, 10)
        val e = engine(); val seen = 10_000_000L
        assertTrue(e.evaluateLink(seen + 5 * min, seen, false, false, "Mac").isEmpty())
        val f = e.evaluateLink(seen + 15 * min, seen, false, false, "Mac")
        assertEquals("15 dakikadır görülmedi.", f[0].text)
        assertTrue(e.evaluateLink(seen + 20 * min, seen, false, false, "Mac").isEmpty())  // aktif
    }

    @Test fun baglantiKoptuSleepingOrReadyOrNeverSeen() {
        overrides["baglanti_koptumac"] = RuleConfig(true, 0, 10)
        val seen = 10_000_000L
        assertTrue(engine(FakeState()).evaluateLink(seen + 30 * min, seen, false, true, "Mac").isEmpty())
        assertTrue(engine(FakeState()).evaluateLink(seen + 30 * min, seen, true, false, "Mac").isEmpty())
        assertTrue(engine(FakeState()).evaluateLink(seen + 30 * min, 0, false, false, "Mac").isEmpty())
    }

    @Test fun describeTexts() {
        assertEquals("%20 ve altı, şarjda değilken", AlertRule.PIL_DUSUK.describe(Subject.TELEFON, RuleConfig(true, 20, 0)))
        assertEquals("%90 ve üstü, 2 dk boyunca", AlertRule.CPU_YUKSEK.describe(Subject.MAC, RuleConfig(true, 90, 2)))
    }
}
