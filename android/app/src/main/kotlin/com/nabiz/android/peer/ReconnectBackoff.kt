package com.nabiz.android.peer

/** Yeniden baglanma beklemesi: 2, 5, 15, 30 sn; sonra 30 sn'de bir (protokol bolum 7). Android'e bagimli degil. */
class ReconnectBackoff(private val stepsMs: LongArray = longArrayOf(2_000, 5_000, 15_000, 30_000)) {
    private var index = 0

    fun next(): Long {
        val d = stepsMs[minOf(index, stepsMs.size - 1)]
        if (index < stepsMs.size) index++
        return d
    }

    fun reset() { index = 0 }
}
