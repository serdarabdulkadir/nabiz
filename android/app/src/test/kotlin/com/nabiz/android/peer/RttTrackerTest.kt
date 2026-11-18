package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RttTrackerTest {
    private val ms = 1_000_000L

    @Test fun measuresRttFromMatchingId() {
        val t = RttTracker()
        val id = t.onSent(0)
        assertEquals(12, t.onPong(id, 12 * ms))
    }

    @Test fun ignoresPongWithoutIdOrUnknownId() {
        val t = RttTracker()
        t.onSent(0)
        assertNull(t.onPong(null, 5 * ms))
        assertNull(t.onPong(999, 5 * ms))
        assertNull(t.medianMs())
    }

    @Test fun duplicatePongCountsOnce() {
        val t = RttTracker()
        val id = t.onSent(0)
        t.onPong(id, 10 * ms)
        assertNull(t.onPong(id, 50 * ms))
        assertEquals(10, t.medianMs())
    }

    @Test fun medianOfLastFiveDropsOldSamples() {
        val t = RttTracker()
        var now = 0L
        var last: Int? = null
        // 100, 10, 20, 30, 40 -> ortanca 30; ardindan 50 gelince 100 pencereden cikar: 10,20,30,40,50 -> 30
        for (d in listOf(100L, 10, 20, 30, 40)) { val id = t.onSent(now); now += d * ms; last = t.onPong(id, now) }
        assertEquals(30, last)
        val id = t.onSent(now)
        assertEquals(30, t.onPong(id, now + 50 * ms))
        val id2 = t.onSent(now)
        assertEquals(40, t.onPong(id2, now + 60 * ms))   // 20,30,40,50,60
    }

    @Test fun idsIncreaseAndResetClears() {
        val t = RttTracker()
        val a = t.onSent(0); val b = t.onSent(0)
        assertNotEquals(a, b)
        t.onPong(a, ms)
        t.reset()
        assertNull(t.medianMs())
        assertNull(t.onPong(b, 2 * ms))
    }
}
