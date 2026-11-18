package com.nabiz.android.phone

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.SystemClock
import android.provider.CallLog
import android.provider.ContactsContract
import androidx.core.content.ContextCompat
import com.nabiz.android.notif.NotifHub
import com.nabiz.android.peer.PeerMessage
import com.nabiz.android.peer.PhoneHost
import com.nabiz.android.peer.PhoneNotif
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/**
 * Telefon ozelliklerinin tek giris noktasi: anahtarlar, sistem izinleri, arama, kisi/arama gecmisi ve bildirim.
 * Mac'ten gelen istekler `handle` ile islenir; izin yokken `error` {izin_yok}.
 * `send`: bagli oturuma mesaj yollar (oturum yoksa sessizce atilir).
 */
class PhoneFeatures(context: Context, private val rawSend: (PeerMessage) -> Unit) : PhoneHost {
    private val app = context.applicationContext
    /** Kanal istisnasi (cerceve, kapali soket) uygulamayi dusurmesin. */
    private val send: (PeerMessage) -> Unit = { m -> try { rawSend(m) } catch (_: Exception) { } }
    val share = ShareSettings(app)
    val controller = PhoneController(app) { share.flags.value }
    private val reader = ContactsReader(app)
    val notifs = NotifHub(app, { share.flags.value }, send, ::refresh)

    private val _perm = MutableStateFlow(computePermState(share.flags.value, grants()))
    /** Mac'e bildirilen durum: anahtar acik VE sistem izni verilmis. */
    val perm: StateFlow<PeerMessage.PermState> = _perm.asStateFlow()

    private val _grants = MutableStateFlow(grants())
    /** Arayuz icin: sistem izinleri (anahtardan bagimsiz). */
    val systemGrants: StateFlow<SystemGrants> = _grants.asStateFlow()

    private fun has(p: String) = ContextCompat.checkSelfPermission(app, p) == PackageManager.PERMISSION_GRANTED

    private fun grants() = SystemGrants(
        bildirimErisimi = notifs.accessGranted(),
        bildirimBagli = notifs.connected,
        cagri = controller.hasCallPermissions(),
        kisiler = has(Manifest.permission.READ_CONTACTS),
        aramaGecmisi = has(Manifest.permission.READ_CALL_LOG),
    )

    /** Anahtar ya da sistem izni degisti (arayuz donusu, izin sonucu, listener baglanti degisimi). */
    fun refresh() {
        controller.ensureStarted()
        val g = grants()
        _grants.value = g
        _perm.value = computePermState(share.flags.value, g)
    }

    fun setShare(key: ShareKey, on: Boolean) {
        share.set(key, on)
        refresh()
    }

    /** NabizService yasam dongusune baglanir: izin degisimini, arama durumunu ve rehber/arama kaydi degisimini Mac'e iletir. */
    fun start(scope: CoroutineScope) {
        refresh()
        scope.launch {
            var prev: PeerMessage.PermState? = null
            perm.collect { p ->
                val before = prev
                prev = p
                if (before == null) return@collect   // oturum kurulurken client zaten yollar
                send(p)
                if (p.bildirimler && !before.bildirimler) {
                    notifs.onSessionStart()
                    send(PeerMessage.NotifList(withContext(Dispatchers.Default) { notifs.list() }))
                }
            }
        }
        scope.launch {
            combine(controller.call, perm.map { it.cagriYonetimi }.distinctUntilChanged()) { c, on -> if (on) c else CallInfo() }
                .distinctUntilChanged()
                .collect { send(it.toMessage(SystemClock.elapsedRealtime())) }
        }
        scope.launch { reader.changes(ContactsContract.Contacts.CONTENT_URI).collect { if (perm.value.kisiler) send(PeerMessage.ContactsChanged()) } }
        scope.launch { reader.changes(CallLog.Calls.CONTENT_URI).collect { if (perm.value.aramaGecmisi) send(PeerMessage.CallLogChanged()) } }
    }

    /** Servis kapanirken: arama dinleyicisi ve alicisi kaldirilir. */
    fun stop() = controller.stop()

    // --- PhoneHost ---

    override fun onSessionStart() = notifs.onSessionStart()

    override fun permState(): PeerMessage.PermState = computePermState(share.flags.value, grants())

    override fun callState(): PeerMessage.CallState =
        if (permState().cagriYonetimi) controller.call.value.toMessage(SystemClock.elapsedRealtime()) else PeerMessage.CallState("bosta")

    override fun notifList(): List<PhoneNotif>? =
        if (permState().bildirimler) notifs.list() else null

    private fun denied(id: Long?, key: String) = listOf<PeerMessage>(PeerMessage.Err("izin_yok", key, id))

    private fun result(id: Long?, r: ActionResult): List<PeerMessage> = when (r) {
        ActionResult.OK -> emptyList()
        ActionResult.NO_PERMISSION -> denied(id, "cagriYonetimi")
        ActionResult.UNSUPPORTED -> listOf(PeerMessage.Err("desteklenmiyor", "Bu telefon aramayı uygulamadan sonlandırmaya izin vermiyor", id))
        ActionResult.INVALID -> listOf(PeerMessage.Err("gecersiz_istek", "numara", id))
        ActionResult.FAILED -> listOf(PeerMessage.Err("hata", "İşlem yapılamadı", id))
    }

    override suspend fun handle(m: PeerMessage): List<PeerMessage> {
        val p = permState()
        // Bildirim istekleri: anahtar/erisim yoksa izin_yok; ikisi de tamam ama dinleyici bagli degilse dinleyici_yok.
        val notifPerm = share.flags.value.bildirimler && notifs.accessGranted()
        val notifOk = notifPerm && notifs.connected
        fun notifDenied(id: Long?) = if (!notifPerm) denied(id, "bildirimler") else listOf<PeerMessage>(PeerMessage.Err("dinleyici_yok", "bildirimler", id))
        return when (m) {
            is PeerMessage.CallAnswer -> if (!p.cagriYonetimi) denied(m.id, "cagriYonetimi") else result(m.id, controller.answer())
            is PeerMessage.CallReject, is PeerMessage.CallHangup ->
                if (!p.cagriYonetimi) denied(m.id, "cagriYonetimi") else result(m.id, controller.endCall())
            is PeerMessage.CallDial -> if (!p.cagriYonetimi) denied(m.id, "cagriYonetimi") else result(m.id, controller.dial(m.numara))
            is PeerMessage.ContactsSync ->
                if (!p.kisiler) denied(m.id, "kisiler")
                else {
                    val off = m.ofset.coerceAtLeast(0)
                    val page = reader.contactsPage(off, m.adet)
                    listOf(PeerMessage.ContactsPage(off, page.toplam, ContactPaging.isLast(off, page.kisiler.size, page.toplam), page.kisiler, m.id))
                }
            is PeerMessage.CallLogSync ->
                if (!p.aramaGecmisi) denied(m.id, "aramaGecmisi")
                else {
                    val off = m.ofset.coerceAtLeast(0)
                    val page = reader.callLogPage(off, m.adet)
                    listOf(PeerMessage.CallLogPage(off, page.toplam, ContactPaging.isLast(off, page.kayitlar.size, page.toplam), page.kayitlar, m.id))
                }
            is PeerMessage.NotifDismiss -> if (!notifOk) notifDenied(m.id) else { notifs.dismiss(m.anahtar); emptyList() }
            is PeerMessage.NotifClear -> if (!notifOk) notifDenied(m.id) else { notifs.clear(); emptyList() }
            is PeerMessage.NotifReply ->
                if (!notifPerm) denied(m.id, "bildirimler")
                else if (!notifOk) listOf(PeerMessage.NotifResult(m.anahtar, "desteklenmiyor", m.id))
                else listOf(PeerMessage.NotifResult(m.anahtar, notifs.reply(m.anahtar, m.metin), m.id))
            else -> emptyList()
        }
    }
}
