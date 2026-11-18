package com.nabiz.android.phone

import com.nabiz.android.peer.PeerMessage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneModelTest {
    @Test fun permNeedsSwitchAndSystemGrant() {
        val none = computePermState(ShareFlags(), SystemGrants(true, true, true, true))
        assertEquals(PeerMessage.PermState(false, false, false, false), none)
        val noSys = computePermState(ShareFlags(true, true, true, true), SystemGrants())
        assertEquals(PeerMessage.PermState(false, false, false, false), noSys)
        val mix = computePermState(ShareFlags(true, true, false, true), SystemGrants(bildirimErisimi = true, cagri = true, kisiler = true, aramaGecmisi = false))
        assertEquals(PeerMessage.PermState(true, true, false, false), mix)
    }

    @Test fun callStateIdleHasNoDirection() {
        val m = CallInfo().toMessage(5_000)
        assertEquals("bosta", m.durum)
        assertNull(m.yon); assertNull(m.sureSn)
    }

    @Test fun durationOnlyWhenActive() {
        val ring = CallInfo("caliyor", "gelen", "555", "Ayşe").toMessage(9_000)
        assertNull(ring.sureSn)
        assertEquals("Ayşe", ring.kisiAdi)
        val open = CallInfo("acik", "gelen", "555", null, startedAt = 1_000).toMessage(43_900)
        assertEquals(42, open.sureSn)
        assertNull(CallInfo("araniyor", "giden", "555", null, 1_000).toMessage(9_000).sureSn)
    }

    @Test fun dialNumberNormalization() {
        assertEquals("+905551112233", normalizeDialNumber("+90 (555) 111-22.33"))
        assertEquals("*#06#", normalizeDialNumber("*#06#"))
        assertNull(normalizeDialNumber(""))
        assertNull(normalizeDialNumber("abc"))
        assertNull(normalizeDialNumber("1".repeat(33)))
    }

    @Test fun pagingRules() {
        assertEquals(40, ContactPaging.clampContacts(null))
        assertEquals(100, ContactPaging.clampContacts(500))
        assertEquals(1, ContactPaging.clampContacts(0))
        assertEquals(100, ContactPaging.clampLog(null))
        assertEquals(200, ContactPaging.clampLog(999))
        assertTrue(ContactPaging.isLast(0, 0, 0))
        assertTrue(ContactPaging.isLast(40, 10, 50))
        assertFalse(ContactPaging.isLast(0, 40, 50))
    }

    @Test fun pageBudgetKeepsAtLeastOne() {
        assertEquals(1, ContactPaging.takeWithinBudget(listOf(10, 10), { 1_000_000 }).size)
        assertEquals(2, ContactPaging.takeWithinBudget(listOf(1, 2, 3), { it }, budget = 5).size)
    }

    @Test fun skipTargetOffsetZeroIsNotEmpty() {
        assertEquals(-1, ContactPaging.skipTarget(0, 5))     // konumlama gerekmez, okunacak satir var
        assertEquals(39, ContactPaging.skipTarget(40, 100))  // ara sayfa
        assertNull(ContactPaging.skipTarget(0, 0))           // bos tablo
        assertNull(ContactPaging.skipTarget(100, 100))       // ofset sonu asti
        assertNull(ContactPaging.skipTarget(-1, 10))
    }

    @Test fun disconnectedListenerMeansNoNotifPerm() {
        val p = computePermState(ShareFlags(bildirimler = true), SystemGrants(bildirimErisimi = true, bildirimBagli = false))
        assertFalse(p.bildirimler)
        assertTrue(computePermState(ShareFlags(bildirimler = true), SystemGrants(bildirimErisimi = true, bildirimBagli = true)).bildirimler)
    }
}
