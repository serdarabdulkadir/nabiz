package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Test

class ReconnectBackoffTest {
    @Test fun stepsThenStays() {
        val b = ReconnectBackoff()
        assertEquals(listOf(2000L, 5000L, 15000L, 30000L, 30000L, 30000L), List(6) { b.next() })
        b.reset()
        assertEquals(2000L, b.next())
    }
}
