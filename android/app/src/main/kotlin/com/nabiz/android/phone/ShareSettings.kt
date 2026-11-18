package com.nabiz.android.phone

import android.content.Context
import com.nabiz.android.peer.PeerMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** "Mac ile paylas" anahtarlari (docs/protokol.md bolum 10). */
data class ShareFlags(
    val bildirimler: Boolean = false,
    val cagriYonetimi: Boolean = false,
    val kisiler: Boolean = false,
    val aramaGecmisi: Boolean = false,
)

/** Sistem izinlerinin o anki durumu. `cagri*`: READ_PHONE_STATE + ANSWER_PHONE_CALLS + CALL_PHONE hepsi. */
data class SystemGrants(
    val bildirimErisimi: Boolean = false,
    val cagri: Boolean = false,
    val kisiler: Boolean = false,
    val aramaGecmisi: Boolean = false,
    /** Bildirim dinleyicisi su an bagli mi (erisim verilmis olsa da baglanana kadar bildirim yollanamaz). */
    val bildirimBagli: Boolean = true,
)

enum class ShareKey(val wire: String) { BILDIRIMLER("bildirimler"), CAGRI("cagriYonetimi"), KISILER("kisiler"), ARAMA_GECMISI("aramaGecmisi") }

/** Tek kaynak: anahtar acik VE sistem izni verilmisse true. */
fun computePermState(flags: ShareFlags, grants: SystemGrants) = PeerMessage.PermState(
    bildirimler = flags.bildirimler && grants.bildirimErisimi && grants.bildirimBagli,
    cagriYonetimi = flags.cagriYonetimi && grants.cagri,
    kisiler = flags.kisiler && grants.kisiler,
    aramaGecmisi = flags.aramaGecmisi && grants.aramaGecmisi,
)

/** Anahtarlar SharedPreferences'ta, varsayilan hepsi kapali. */
class ShareSettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("nabiz_share", Context.MODE_PRIVATE)
    private val _flags = MutableStateFlow(read())
    val flags: StateFlow<ShareFlags> = _flags.asStateFlow()

    private fun read() = ShareFlags(
        prefs.getBoolean(ShareKey.BILDIRIMLER.wire, false),
        prefs.getBoolean(ShareKey.CAGRI.wire, false),
        prefs.getBoolean(ShareKey.KISILER.wire, false),
        prefs.getBoolean(ShareKey.ARAMA_GECMISI.wire, false),
    )

    fun set(key: ShareKey, on: Boolean) {
        prefs.edit().putBoolean(key.wire, on).apply()
        _flags.value = read()
    }
}
