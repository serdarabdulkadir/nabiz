package com.nabiz.android.service

import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkReason
import com.nabiz.android.peer.LinkState
import com.nabiz.android.ui.Format

/** Hizli Ayarlar kutucugunun icerigi (saf, birim testli). */
data class TileModel(val subtitle: String, val active: Boolean) {
    companion object {
        fun from(s: LinkState): TileModel {
            if (s.phase != LinkPhase.READY) {
                return TileModel(if (s.reason == LinkReason.SLEEPING) "Uykuda" else "Bağlı değil", false)
            }
            val cpu = s.macSnap?.cpu?.total?.let { "CPU $it%" } ?: "CPU ${Format.NONE}"
            val bat = s.macSnap?.battery?.level?.let { "%$it" } ?: Format.NONE
            return TileModel("$cpu · $bat", true)
        }
    }
}
