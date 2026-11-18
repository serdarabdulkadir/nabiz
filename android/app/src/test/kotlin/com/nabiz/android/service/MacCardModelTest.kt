package com.nabiz.android.service

import com.nabiz.android.peer.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MacCardModelTest {
    @Test fun disconnected() {
        val m = MacCardModel.from(LinkState(phase = LinkPhase.SEARCHING))
        assertEquals("Mac aranıyor…", m.text); assertFalse(m.showActions); assertNull(m.progress)
    }

    @Test fun connected() {
        val snap = Snapshot(1, cpu = CpuStats(23), mem = MemStats(61, 100), disk = DiskStats(72, 100), battery = BatteryStats(88, false))
        val m = MacCardModel.from(LinkState(phase = LinkPhase.READY, macName = "MacBook", macSnap = snap))
        assertEquals("MacBook · %88", m.title)
        assertEquals("CPU 23% · RAM 61% · Disk 72%", m.text)
        assertEquals(23, m.progress); assertEquals("CPU 23", m.shortCritical)
        assertEquals(listOf("yenile", "kilitle", "uyut"), m.actions.map { it.eylem })
    }

    @Test fun missingValuesShowDashes() {
        val m = MacCardModel.from(LinkState(phase = LinkPhase.READY, macName = "Mac", macSnap = Snapshot(1)))
        assertEquals("CPU -- · RAM -- · Disk --", m.text); assertNull(m.progress); assertEquals("Mac", m.title)
    }

    private fun ready(ms: PeerMessage.MacState?, snap: Snapshot = Snapshot(1, cpu = CpuStats(23), mem = MemStats(61, 100), disk = DiskStats(88, 100), battery = BatteryStats(31, false, minutes = 200))) =
        LinkState(phase = LinkPhase.READY, macName = "MacBook", macSnap = snap, macState = ms)

    @Test fun actionsFollowMacState() {
        val ac = { ms: PeerMessage.MacState? -> MacCardModel.actionsFor(ready(ms)).map { it.eylem } }
        assertEquals(listOf("yenile", "uyut"), ac(PeerMessage.MacState(true, false, false)))
        assertEquals(listOf("yenile", "uyandir", "uyut"), ac(PeerMessage.MacState(false, true, false)))
        assertEquals(emptyList<String>(), ac(PeerMessage.MacState(false, false, true)))
        assertTrue(MacCardModel.from(ready(PeerMessage.MacState(true, false, false))).title.endsWith("Kilitli"))
    }

    @Test fun sleepingCard() {
        val st = LinkState(phase = LinkPhase.SEARCHING, macName = "MacBook", reason = LinkReason.SLEEPING, lastSeenAt = 5)
        val m = MacCardModel.from(st, timeFmt = { "14:32" })
        assertEquals("Mac uykuda · son görülme 14:32", m.text); assertFalse(m.showActions)
        assertEquals(LinkReason.SLEEPING, disconnectReason(LinkReason.LOST, PeerMessage.MacState(false, false, true)))
        assertEquals(LinkReason.LOST, disconnectReason(LinkReason.LOST, PeerMessage.MacState(false, false, false)))
    }

    @Test fun styles() {
        val st = ready(null)
        val u = MacCardModel.from(st, NotifStyle.UCLU)
        assertEquals("CPU 23 · RAM 61 · Disk 88", u.text)
        assertEquals(300, u.segments.sumOf { it.length }); assertEquals(Tone.WARN, u.segments.first { it.length == 88 }.tone)
        val k = MacCardModel.from(st, NotifStyle.KOMPAKT)
        assertEquals("MacBook · %31 pil", k.title); assertEquals("CPU 23% · RAM 61%", k.text); assertNull(k.progress)
        val a = MacCardModel.from(st, NotifStyle.AYRINTILI)
        assertEquals(8, a.bigText!!.lines().size)
        val p = MacCardModel.from(st, NotifStyle.PIL)
        assertEquals(31, p.progress); assertEquals("Pilde · kalan 3sa 20dk", p.text); assertEquals("%31", p.shortCritical)
        assertEquals(listOf(31, 69), p.segments.map { it.length })
    }

    @Test fun chipPicksMostCritical() {
        assertEquals("CPU 23", MacCardModel.criticalChip(23, 61, 70))
        assertEquals("RAM 80", MacCardModel.criticalChip(23, 80, 70))
        assertEquals("DSK 88", MacCardModel.criticalChip(23, 61, 88))
        assertEquals("CPU 95", MacCardModel.criticalChip(95, 91, 70))
        assertEquals(null, MacCardModel.criticalChip(null, null, null))
        val m = MacCardModel.from(ready(null), NotifStyle.UCLU)
        assertEquals("DSK 88", m.shortCritical)
    }

    @Test fun triSegmentsAndPoints() {
        val m = MacCardModel.from(ready(null), NotifStyle.UCLU)
        assertEquals(300, m.progressMax); assertEquals(300, m.segments.sumOf { it.length })
        assertEquals(listOf(100, 200), m.points.map { it.at })
        val c = MacCardModel.from(ready(null))
        assertEquals(listOf(75, 90), c.points.map { it.at }); assertEquals("Yerel ağ", c.subText)
    }

    @Test fun sleepingChip() {
        val st = LinkState(phase = LinkPhase.SEARCHING, macName = "MacBook", reason = LinkReason.SLEEPING, lastSeenAt = 5)
        assertEquals("Uykuda", MacCardModel.from(st).shortCritical)
    }
}
