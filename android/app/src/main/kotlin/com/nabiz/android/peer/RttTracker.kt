package com.nabiz.android.peer

/**
 * Ping-pong gecikme olcumu (docs/protokol.md bolum 7, Gecikme). Saf: zaman (monoton, nanosaniye) disaridan verilir.
 * Gosterilen deger son `window` olcumun ortancasidir. Tek iplik / dis kilit altinda kullanilir.
 */
class RttTracker(private val window: Int = 5, private val maxPending: Int = 8) {
    private val pending = LinkedHashMap<Long, Long>()
    private val samples = ArrayDeque<Long>()
    private var nextId = 1L

    /** Yeni ping icin id verir ve gonderim anini kaydeder. */
    fun onSent(nowNs: Long): Long {
        val id = nextId++
        pending[id] = nowNs
        while (pending.size > maxPending) pending.remove(pending.keys.first())
        return id
    }

    /** Pong geldi: bilinen id ise olcumu ekler ve ortancayi (ms) dondurur; `id`siz ya da bilinmeyen id yok sayilir (null). */
    fun onPong(id: Long?, nowNs: Long): Int? {
        if (id == null) return null
        val sent = pending.remove(id) ?: return null
        samples.addLast(maxOf(0L, nowNs - sent))
        while (samples.size > window) samples.removeFirst()
        return medianMs()
    }

    fun medianMs(): Int? {
        if (samples.isEmpty()) return null
        val sorted = samples.sorted()
        return Math.round(sorted[sorted.size / 2] / 1_000_000.0).toInt()
    }

    fun reset() {
        pending.clear()
        samples.clear()
    }
}
