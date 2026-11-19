package com.nabiz.android.peer

/** Yeniden baglanma beklemesi: 1, 2, 5, 10, 30 sn; sonra 30 sn'de bir (protokol bolum 11). Android'e bagimli degil. */
class ReconnectBackoff(private val stepsMs: LongArray = longArrayOf(1_000, 2_000, 5_000, 10_000, 30_000)) {
    private var index = 0

    fun next(): Long {
        val d = stepsMs[minOf(index, stepsMs.size - 1)]
        if (index < stepsMs.size) index++
        return d
    }

    /** En uzun bekleme (surum uyumsuzlugu gibi kendiliginden duzelmeyen durumlar); sonraki denemeler de en uzunda kalir. */
    fun longest(): Long {
        index = stepsMs.size
        return stepsMs.last()
    }

    fun reset() { index = 0 }
}
