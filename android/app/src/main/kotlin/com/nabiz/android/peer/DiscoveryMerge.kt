package com.nabiz.android.peer

/** NSD + UDP + son adres sonuclarini `id` ile birlestirir (saf mantik, Android'e bagimli degil). */
object DiscoveryMerge {
    const val TTL_MS = 60_000L

    /**
     * `incoming` ayni id'li kaydin yerini alir; yalniz "son adres" kaydi gercek bir kesfi ezmez.
     * Gercek kesif ayni id'li LAST kaydinin yerine gecer. Siralama: LAST'ten once kesifler, sonra ad.
     */
    fun merge(list: List<MacService>, incoming: MacService): List<MacService> {
        val old = list.firstOrNull { it.id == incoming.id }
        val next = when {
            old == null -> incoming
            incoming.source == MacSource.LAST && old.source != MacSource.LAST -> old
            else -> incoming
        }
        return (list.filterNot { it.id == incoming.id } + next).sortedWith(compareBy({ it.source == MacSource.LAST }, { it.name.lowercase() }))
    }

    /** `TTL_MS` kadar gorulmeyenleri dusurur. */
    fun prune(list: List<MacService>, now: Long): List<MacService> = list.filter { now - it.lastSeen <= TTL_MS }

    /** Bu id'nin "son adres" kaydini kaldirir (baglanti denemesi basarisiz). */
    fun dropLast(list: List<MacService>, id: String): List<MacService> =
        list.filterNot { it.id == id && it.source == MacSource.LAST }
}
