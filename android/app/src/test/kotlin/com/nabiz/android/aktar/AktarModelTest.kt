package com.nabiz.android.aktar

import com.nabiz.android.peer.AktarFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AktarModelTest {
    private val files = listOf(AktarFile(0, "a.jpg", 1_048_576), AktarFile(1, "b.mov", 3_145_728))
    private fun t(st: TransferStatus, done: Long = 0, dir: TransferDir = TransferDir.OUT) =
        TransferInfo("x", dir, "MacBook Air", files, st, doneBytes = done, speedBps = 2_097_152)

    @Test fun percentAndTitle() {
        assertEquals(25, t(TransferStatus.ACTIVE, 1_048_576).percent)
        assertEquals("2 dosya", t(TransferStatus.ACTIVE).title)
        assertEquals("a.jpg", t(TransferStatus.ACTIVE).copy(files = files.take(1)).title)
        assertTrue(t(TransferStatus.WAITING).running)
        assertTrue(!t(TransferStatus.OFFERED).running)
    }

    @Test fun texts() {
        assertEquals("MacBook Air 2 dosya göndermek istiyor", AktarText.offerTitle("MacBook Air", 2))
        assertEquals("3 öğe paylaş", AktarText.shareTitle(3))
        assertEquals("Orijinal kalite · 4.0 MB", AktarText.shareSub(4_194_304))
        assertEquals("Orijinal kalite", AktarText.shareSub(null))
        assertEquals("Mac'te Aktar kapalı", AktarText.rejectReason("kapali"))
        assertTrue(AktarText.subtitle(t(TransferStatus.ACTIVE, 1_048_576)).contains("2.0 MB/s"))
        assertEquals("2 dosya alındı", AktarText.resultTitle(t(TransferStatus.DONE, dir = TransferDir.IN)))
    }

    @Test fun speedMeterSmooths() {
        val m = SpeedMeter()
        assertEquals(0L, m.update(1000, 0))
        assertEquals(0L, m.update(1200, 1_000_000))            // 500 ms dolmadi
        assertEquals(2_000_000L, m.update(1500, 1_000_000))    // 1 MB / 0.5 sn
    }
}
