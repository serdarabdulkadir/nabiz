package com.nabiz.android.ui

import com.nabiz.android.peer.AiLimit
import com.nabiz.android.peer.AiProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

class AiFormatTest {
    private fun l(id: String, pct: Int, general: Boolean, tuk: Long? = null) = AiLimit(id, id, pct, null, general, tuk)
    private val utc = ZoneId.of("UTC")
    private fun at(h: Int, m: Int, day: Int = 20) = ZonedDateTime.of(2026, 11, day, h, m, 0, 0, utc).toEpochSecond()

    @Test fun frontPrefersGeneralInOrder() {
        val ls = listOf(l("a", 10, true), l("b", 90, false), l("c", 50, true), l("d", 70, true))
        assertEquals(listOf("a", "b"), AiFormat.frontLimits(ls).map { it.id })
    }

    @Test fun frontHotNonGeneralReplacesSecond() {
        val ls = listOf(l("a", 10, true), l("b", 30, true), l("c", 95, false), l("d", 91, false))
        assertEquals(listOf("a", "c"), AiFormat.frontLimits(ls).map { it.id })
        // ikinci genel daha doluysa o kalir; %90 alti genel-olmayan girmez
        assertEquals(listOf("a", "b"), AiFormat.frontLimits(listOf(l("a", 10, true), l("b", 99, true), l("c", 95, false))).map { it.id })
        assertEquals(listOf("a", "b"), AiFormat.frontLimits(listOf(l("a", 10, true), l("b", 30, true), l("c", 80, false))).map { it.id })
    }

    @Test fun frontFillsWithHighestWhenFewGeneral() {
        val ls = listOf(l("a", 10, true), l("b", 30, false), l("c", 95, false))
        assertEquals(listOf("a", "c"), AiFormat.frontLimits(ls).map { it.id })
        assertEquals(listOf("b", "c").sorted(), AiFormat.frontLimits(listOf(l("b", 30, false), l("c", 95, false))).map { it.id }.sorted())
        assertEquals(emptyList<AiLimit>(), AiFormat.frontLimits(emptyList()))
    }

    @Test fun remainingText() {
        assertEquals("2 sa 10 dk", AiFormat.remaining(7800))
        assertEquals("45 dk", AiFormat.remaining(2700))
        assertEquals("3 g 4 sa", AiFormat.remaining(3 * 86400 + 4 * 3600 + 120))
        assertEquals("2 sa", AiFormat.remaining(7200))
        assertEquals("1 dk'dan az", AiFormat.remaining(20))
    }

    @Test fun suffixByReading() {
        assertEquals("da", AiFormat.suffix(36))   // altmis alti... otuz alti
        assertEquals("te", AiFormat.suffix(14))
        assertEquals("de", AiFormat.suffix(20))
        assertEquals("ta", AiFormat.suffix(40))
        assertEquals("da", AiFormat.suffix(10))
        assertEquals("de", AiFormat.suffix(12))
    }

    @Test fun resetTextSameDayAndOtherDay() {
        val now = at(10, 0)
        assertEquals("14:36'da açılır", AiFormat.resetText(at(14, 36), now, utc))
        assertEquals("15:00'te açılır", AiFormat.resetText(at(15, 0), now, utc))
        assertEquals("Cum 14:36'da açılır", AiFormat.resetText(at(14, 36, 27), now, utc))   // 27 Kasim 2026 Cuma
        assertNull(AiFormat.resetText(at(9, 0), now, utc))
        assertNull(AiFormat.resetText(null, now, utc))
    }

    @Test fun titleWithAccount() {
        assertEquals("Claude", AiFormat.title(AiProvider("claude", "Claude")))
        assertEquals("Claude · İş", AiFormat.title(AiProvider("claude", "Claude", hesapId = "u1", hesap = "İş")))
    }

    @Test fun noteRules() {
        val full = AiProvider("x", "X", limitler = listOf(l("a", 100, true, 500), l("b", 10, true)), notu = "n")
        assertEquals("Doldu", AiFormat.note(full))
        val burn = AiProvider("x", "X", limitler = listOf(l("a", 42, true, 7800), l("b", 10, true, 90000)))
        assertEquals("Bu hızla 2 saat 10 dakikada tükenir", AiFormat.note(burn))
        assertEquals("$15", AiFormat.note(AiProvider("x", "X", notu = "$15", limitler = listOf(l("a", 5, true)))))
        assertNull(AiFormat.note(AiProvider("x", "X")))
    }

    @Test fun untilResetAndLong() {
        assertEquals("3 sa 50 dk", AiFormat.untilReset(1000 + 3 * 3600 + 50 * 60, 1000))
        assertEquals("6 g 17 sa", AiFormat.untilReset(0 + 6 * 86400 + 17 * 3600 + 300, 0))
        assertNull(AiFormat.untilReset(null, 5)); assertNull(AiFormat.untilReset(5, 5))
        assertEquals("33 dakika", AiFormat.remainingLong(33 * 60L))
        assertEquals("Bu hızla 33 dakikada tükenir", AiFormat.tempo(AiProvider("x", "X", limitler = listOf(l("a", 5, true, 33 * 60L)))))
        assertEquals("Bu hızla 3 gün 4 saatte tükenir", AiFormat.tempo(AiProvider("x", "X", limitler = listOf(l("a", 5, true, 3 * 86400L + 4 * 3600)))))
        assertNull(AiFormat.tempo(AiProvider("x", "X", notu = "n", limitler = listOf(l("a", 5, true)))))
    }
}
