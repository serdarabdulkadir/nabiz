package com.nabiz.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FormatTest {
    @Test fun formats() {
        assertEquals(50, Format.percent(1, 2)); assertNull(Format.percent(1, 0))
        assertEquals("1.5 GB", Format.bytes(1_610_612_736)); assertEquals("512 MB", Format.bytes(536_870_912))
        assertEquals("2.0 MB/s", Format.rate(2_097_152)); assertEquals("10 KB/s", Format.rate(10_240)); assertEquals("5 B/s", Format.rate(5))
        assertEquals("2g 3sa", Format.uptime(2 * 86400L + 3 * 3600)); assertEquals("1sa 5dk", Format.uptime(3900))
    }
}
