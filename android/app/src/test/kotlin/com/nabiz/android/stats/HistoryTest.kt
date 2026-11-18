package com.nabiz.android.stats

import org.junit.Assert.assertEquals
import org.junit.Test

class HistoryTest {
    @Test fun dropsPointsOlderThanWindow() {
        val b = HistoryBuffer()
        b.add(0, 1); b.add(300_000, 2); b.add(700_000, 3)
        assertEquals(listOf(2, 3), b.points().map { it.value })
    }

    @Test fun thinsTooFrequentSamples() {
        val b = HistoryBuffer(minGapMs = 1000)
        b.add(0, 1); b.add(500, 2); b.add(1000, 3)
        assertEquals(listOf(1, 3), b.points().map { it.value })
    }

    @Test fun capsSize() {
        val b = HistoryBuffer(windowMs = Long.MAX_VALUE / 2, minGapMs = 0, maxSize = 3)
        for (i in 1..5) b.add(i.toLong(), i)
        assertEquals(listOf(3, 4, 5), b.points().map { it.value })
    }

    @Test fun storeKeepsSeriesPerMetric() {
        val s = HistoryStore()
        s.addMac(0, com.nabiz.android.peer.Snapshot(1, cpu = com.nabiz.android.peer.CpuStats(40)))
        assertEquals(listOf(40), s.macCpuSeries.value.map { it.value })
        assertEquals(0, s.macMemory.value.size)
    }
}
