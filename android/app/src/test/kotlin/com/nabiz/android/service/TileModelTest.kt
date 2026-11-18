package com.nabiz.android.service

import com.nabiz.android.peer.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TileModelTest {
    @Test fun connected() {
        val snap = Snapshot(1, cpu = CpuStats(23), battery = BatteryStats(62, false))
        val m = TileModel.from(LinkState(phase = LinkPhase.READY, macSnap = snap))
        assertEquals("CPU 23% · %62", m.subtitle); assertTrue(m.active)
    }

    @Test fun disconnectedAndSleeping() {
        assertEquals("Bağlı değil", TileModel.from(LinkState()).subtitle)
        val z = TileModel.from(LinkState(phase = LinkPhase.SEARCHING, reason = LinkReason.SLEEPING))
        assertEquals("Uykuda", z.subtitle); assertFalse(z.active)
    }
}
