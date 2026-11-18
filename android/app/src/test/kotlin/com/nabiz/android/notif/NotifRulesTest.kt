package com.nabiz.android.notif

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NotifRulesTest {
    private val own = "com.nabiz.android"
    private fun n(
        key: String = "k", pkg: String = "com.whatsapp", title: String? = "Ayşe", text: String? = "Merhaba",
        time: Long = 1_795_000_100_000, ongoing: Boolean = false, summary: Boolean = false, category: String? = null,
        reply: Boolean = false, clearable: Boolean = true,
    ) = RawNotif(key, pkg, "WhatsApp", title, text, time, ongoing, summary, category, reply, clearable)

    @Test fun acceptsNormal() = assertTrue(NotifRules.accept(n(), own))

    @Test fun rejectsOwnOngoingSummaryCallTransport() {
        assertFalse(NotifRules.accept(n(pkg = own), own))
        assertFalse(NotifRules.accept(n(ongoing = true), own))
        assertFalse(NotifRules.accept(n(summary = true), own))
        assertFalse(NotifRules.accept(n(category = NotifRules.CATEGORY_CALL), own))
        assertFalse(NotifRules.accept(n(category = NotifRules.CATEGORY_TRANSPORT), own))
    }

    @Test fun rejectsEmptyTitleAndText() {
        assertFalse(NotifRules.accept(n(title = null, text = null), own))
        assertFalse(NotifRules.accept(n(title = " ", text = ""), own))
        assertTrue(NotifRules.accept(n(title = null, text = "x"), own))
        assertTrue(NotifRules.accept(n(title = "x", text = null), own))
    }

    @Test fun truncatesTextTo400() {
        val item = NotifRules.toItem(n(text = "a".repeat(900)), null)
        assertEquals(400, item.metin!!.length)
        assertEquals("kisa", NotifRules.toItem(n(text = "kisa"), null).metin)
    }

    @Test fun truncateKeepsSurrogatePairs() {
        val s = "a".repeat(399) + "😀" + "b"
        val t = NotifRules.truncate(s)
        assertEquals(399, t.length)
    }

    @Test fun itemMapsFields() {
        val item = NotifRules.toItem(n(key = "0|x|1", reply = true, clearable = false), "AAAA")
        assertEquals("0|x|1", item.anahtar)
        assertEquals("com.whatsapp", item.paket)
        assertEquals("WhatsApp", item.uygulama)
        assertEquals(1_795_000_100L, item.zaman)
        assertTrue(item.yanitlanabilir)
        assertFalse(item.kapatilabilir)
        assertEquals("AAAA", item.ikon)
    }

    @Test fun oversizedIconDropped() {
        assertNull(NotifRules.toItem(n(), "A".repeat(NotifRules.MAX_ICON_BASE64 + 1)).ikon)
    }

    @Test fun listIsNewestFirstAndCappedAt50() {
        val all = (1..70).map { n(key = "k$it", time = it * 1000L) } + n(key = "own", pkg = own, time = 999_000)
        val sel = NotifRules.select(all, own)
        assertEquals(50, sel.size)
        assertEquals("k70", sel.first().key)
        assertEquals("k21", sel.last().key)
    }

    @Test fun throttleAllowsOnePerSecondPerKey() {
        val t = NotifThrottle()
        assertEquals(0L, t.offer("a", 10_000))
        assertEquals(600L, t.offer("a", 10_400))          // bekler
        assertEquals(-1L, t.offer("a", 10_500))           // zaten bekleyen var
        assertEquals(0L, t.offer("b", 10_500))            // baska anahtar serbest
        t.fire("a", 11_000)
        assertEquals(0L, t.offer("a", 12_001))
        assertTrue(t.offer("a", 12_100) > 0)
    }

    @Test fun throttleForgetResets() {
        val t = NotifThrottle()
        t.offer("a", 1_000)
        t.forget("a")
        assertEquals(0L, t.offer("a", 1_100))
    }

    @Test fun titleAndAppTruncatedTo200() {
        val item = NotifRules.toItem(n(title = "t".repeat(500)).copy(appName = "a".repeat(500)), null)
        assertEquals(200, item.baslik!!.length)
        assertEquals(200, item.uygulama.length)
    }

    private fun item(i: Int, icon: String?) = com.nabiz.android.peer.PhoneNotif("k$i", "p", "A", "b", "m".repeat(400), 1, false, true, icon)

    @Test fun fitKeepsSmallListUntouched() {
        val l = listOf(item(1, "AAAA"), item(2, null))
        assertEquals(l, NotifRules.fit(l))
    }

    @Test fun fitDropsIconsFirstThenTrimsFromEnd() {
        val icon = "A".repeat(6000)
        val l = (1..50).map { item(it, icon) }                 // ~50 * (6000+1900) > 300 KB
        val noIconSize = NotifRules.fit(l, budget = 300_000)
        assertEquals(50, noIconSize.size)                      // ikonsuz sigiyor
        assertTrue(noIconSize.all { it.ikon == null })
        val trimmed = NotifRules.fit(l, budget = 20_000)
        assertTrue(trimmed.size in 1 until 50)
        assertEquals("k1", trimmed.first().anahtar)            // sondan kirpilir
    }
}
