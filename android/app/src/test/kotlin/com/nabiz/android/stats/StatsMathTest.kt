package com.nabiz.android.stats

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StatsMathTest {
    @Test fun memPressure() {
        assertEquals("critical", StatsMath.memPressure(1000, 10000, true))
        assertEquals("warn", StatsMath.memPressure(1000, 10000, false))
        assertEquals("normal", StatsMath.memPressure(3000, 10000, false))
    }

    @Test fun thermal() {
        assertEquals("normal", StatsMath.thermal(0)); assertEquals("normal", StatsMath.thermal(1))
        assertEquals("warn", StatsMath.thermal(2)); assertEquals("critical", StatsMath.thermal(3)); assertEquals("critical", StatsMath.thermal(6))
        assertNull(StatsMath.thermal(-1))
    }

    @Test fun rate() {
        assertEquals(1000L, StatsMath.rate(0, 2000, 2000))
        assertNull(StatsMath.rate(-1, 10, 1000)); assertNull(StatsMath.rate(10, 5, 1000)); assertNull(StatsMath.rate(0, 5, 0))
    }

    @Test fun batteryAndTemp() {
        assertEquals(50, StatsMath.batteryPercent(50, 100)); assertNull(StatsMath.batteryPercent(-1, 100))
        assertEquals(31.5, StatsMath.tempC(315)!!, 0.0); assertNull(StatsMath.tempC(Int.MIN_VALUE))
    }
}
