package com.nabiz.android.stats

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class HistoryPoint(val atMs: Long, val value: Int)

/** Son `windowMs` (varsayilan 10 dk) icin halka tampon; saf, JVM birim testli. Cok sik ornek `minGapMs` ile seyreltilir. */
class HistoryBuffer(private val windowMs: Long = 600_000, private val minGapMs: Long = 1_000, private val maxSize: Int = 700) {
    private val items = ArrayDeque<HistoryPoint>()

    fun add(nowMs: Long, value: Int) {
        val last = items.lastOrNull()
        if (last != null && nowMs - last.atMs < minGapMs) return
        items.addLast(HistoryPoint(nowMs, value))
        while (items.isNotEmpty() && nowMs - items.first().atMs > windowMs) items.removeFirst()
        while (items.size > maxSize) items.removeFirst()
    }

    fun points(): List<HistoryPoint> = items.toList()
}

/** Telefon (pil, bellek) ve Mac (CPU, bellek) serileri; servis yazar, arayuz okur. */
class HistoryStore {
    private class Series {
        val buf = HistoryBuffer()
        val flow = MutableStateFlow<List<HistoryPoint>>(emptyList())
        fun add(now: Long, v: Int?) { if (v != null) { buf.add(now, v); flow.value = buf.points() } }
    }

    private val phoneBat = Series()
    private val phoneMem = Series()
    private val macCpu = Series()
    private val macMem = Series()

    val phoneBattery: StateFlow<List<HistoryPoint>> = phoneBat.flow.asStateFlow()
    val phoneMemory: StateFlow<List<HistoryPoint>> = phoneMem.flow.asStateFlow()
    val macCpuSeries: StateFlow<List<HistoryPoint>> = macCpu.flow.asStateFlow()
    val macMemory: StateFlow<List<HistoryPoint>> = macMem.flow.asStateFlow()

    @Synchronized
    fun addPhone(now: Long, snap: com.nabiz.android.peer.Snapshot) {
        phoneBat.add(now, snap.battery?.level)
        phoneMem.add(now, snap.mem?.let { pct(it.used, it.total) })
    }

    @Synchronized
    fun addMac(now: Long, snap: com.nabiz.android.peer.Snapshot) {
        macCpu.add(now, snap.cpu?.total?.coerceIn(0, 100))
        macMem.add(now, snap.mem?.let { pct(it.used, it.total) })
    }

    private fun pct(used: Long, total: Long): Int? = if (total <= 0) null else (used * 100 / total).toInt().coerceIn(0, 100)
}
