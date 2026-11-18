package com.nabiz.android.notif

import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.nabiz.android.peer.PeerMessage
import com.nabiz.android.peer.PhoneNotif
import com.nabiz.android.phone.ShareFlags
import java.io.ByteArrayOutputStream
import java.util.Base64

/**
 * NotifListener ile Mac kanali arasindaki kopru: StatusBarNotification'i RawNotif'e cevirir,
 * kurallari ve hiz sinirini uygular, Mac'ten gelen kapat/temizle/yanitla isteklerini listener'a yapar.
 */
class NotifHub(
    private val ctx: Context,
    private val flags: () -> ShareFlags,
    sendRaw: (PeerMessage) -> Unit,
    private val onChange: () -> Unit,
) {
    private val send: (PeerMessage) -> Unit = { m -> try { sendRaw(m) } catch (_: Exception) { } }
    private val own = ctx.packageName
    private val main = Handler(Looper.getMainLooper())
    private val throttle = NotifThrottle()
    private val iconSent = HashSet<String>()
    private val announced = HashSet<String>()
    @Volatile private var listener: NotificationListenerService? = null

    val connected: Boolean get() = listener != null

    /** Sistem "Bildirim erisimi" bu uygulamaya verilmis mi (listener henuz baglanmamis olabilir). */
    fun accessGranted(): Boolean =
        androidx.core.app.NotificationManagerCompat.getEnabledListenerPackages(ctx).contains(own)

    fun onConnected(l: NotificationListenerService) { listener = l; onChange() }
    fun onDisconnected(l: NotificationListenerService) { if (listener === l) listener = null; onChange() }

    private fun active() = flags().bildirimler && listener != null

    @Synchronized
    fun onSessionStart() { iconSent.clear(); announced.clear(); throttle.clear() }

    // --- tel -> mac ---

    @Synchronized
    fun list(): List<PhoneNotif> {
        if (!active()) return emptyList()
        val seen = HashSet<String>()
        val selected = NotifRules.select(activeSbns().map(::raw), own)
        val items = NotifRules.fit(selected.map { n ->
            NotifRules.toItem(n, if (seen.add(n.packageName)) iconFor(n.packageName) else null)
        })
        // Yalniz gercekten giden ikonlar ve bildirimler "gonderildi" sayilir.
        for (i in items) { announced += i.anahtar; if (i.ikon != null) iconSent += i.paket }
        return items
    }

    @Synchronized
    fun onPosted(sbn: StatusBarNotification) {
        if (!active()) return
        val n = raw(sbn)
        if (!NotifRules.accept(n, own)) {
            if (announced.remove(n.key)) send(PeerMessage.NotifRemoved(n.key))
            throttle.forget(n.key)
            return
        }
        val wait = throttle.offer(n.key, System.currentTimeMillis())
        when {
            wait == 0L -> emit(n)
            wait > 0L -> main.postDelayed({ trailing(n.key) }, wait)
        }
    }

    @Synchronized
    fun onRemoved(sbn: StatusBarNotification) {
        throttle.forget(sbn.key)
        if (active() && announced.remove(sbn.key)) send(PeerMessage.NotifRemoved(sbn.key))
    }

    /** Hiz siniri nedeniyle bekleyen gonderim: o anki son hal yollanir. */
    @Synchronized
    private fun trailing(key: String) {
        throttle.fire(key, System.currentTimeMillis())
        if (!active()) return
        val sbn = activeSbns().firstOrNull { it.key == key } ?: return
        val n = raw(sbn)
        if (NotifRules.accept(n, own)) emit(n)
    }

    private fun emit(n: RawNotif) {
        announced += n.key
        val item = NotifRules.toItem(n, iconFor(n.packageName))
        if (item.ikon != null) iconSent += n.packageName
        send(PeerMessage.NotifPosted(item))
    }

    // --- mac -> tel ---

    fun dismiss(key: String) {
        try { listener?.cancelNotification(key) } catch (_: Exception) { }
    }

    /** Kapatilabilir ve Mac'e gosterilen tum bildirimleri kapatir. */
    fun clear() {
        val keys = activeSbns().map(::raw).filter { NotifRules.accept(it, own) && it.clearable }.map { it.key }
        if (keys.isEmpty()) return
        try { listener?.cancelNotifications(keys.toTypedArray()) } catch (_: Exception) { }
    }

    /** `tamam` / `bulunamadi` / `desteklenmiyor` / `hata`. */
    fun reply(key: String, text: String): String {
        val sbn = activeSbns().firstOrNull { it.key == key } ?: return "bulunamadi"
        val action = replyAction(sbn.notification) ?: return "desteklenmiyor"
        if (text.isBlank()) return "hata"
        val inputs = action.remoteInputs.filter { it.allowFreeFormInput }.toTypedArray()
        return try {
            val fill = Intent()
            val results = Bundle()
            for (ri in inputs) results.putCharSequence(ri.resultKey, text)
            RemoteInput.addResultsToIntent(inputs, fill, results)
            action.actionIntent.send(ctx, 0, fill)
            "tamam"
        } catch (_: Exception) {   // PendingIntent.CanceledException dahil
            "hata"
        }
    }

    // --- Android -> ara veri ---

    private fun activeSbns(): List<StatusBarNotification> = try {
        listener?.activeNotifications?.toList().orEmpty()
    } catch (_: Exception) { emptyList() }

    private fun replyAction(n: Notification): Notification.Action? =
        n.actions?.firstOrNull { a -> a.actionIntent != null && a.remoteInputs?.any { it.allowFreeFormInput } == true }

    private fun raw(sbn: StatusBarNotification): RawNotif {
        val n = sbn.notification
        val ex = n.extras
        val text = ex?.getCharSequence(Notification.EXTRA_TEXT) ?: ex?.getCharSequence(Notification.EXTRA_BIG_TEXT)
        return RawNotif(
            key = sbn.key,
            packageName = sbn.packageName,
            appName = appName(sbn.packageName),
            title = ex?.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            text = text?.toString(),
            postTimeMs = sbn.postTime,
            ongoing = sbn.isOngoing || (n.flags and Notification.FLAG_ONGOING_EVENT) != 0,
            groupSummary = (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0,
            category = n.category,
            replyable = replyAction(n) != null,
            clearable = sbn.isClearable,
        )
    }

    private fun appName(pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    /** Paket basina oturumda bir kez; sonraki bildirimlerde null (Mac paket onbellegini kullanir). Gonderim sonrasi `iconSent`e eklenir. */
    private fun iconFor(pkg: String): String? =
        if (pkg in iconSent) null else AppIcon.base64(ctx, pkg)
}

/** Uygulama simgesi: en cok 64 px PNG, standart base64, en cok 6 KB; sigmazsa kucultulur, yine olmazsa null. */
internal object AppIcon {
    fun base64(ctx: Context, pkg: String): String? {
        val drawable = try { ctx.packageManager.getApplicationIcon(pkg) } catch (_: Exception) { return null }
        for (px in intArrayOf(64, 48, 32)) {
            try {
                val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
                drawable.setBounds(0, 0, px, px)
                drawable.draw(Canvas(bmp))
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                bmp.recycle()
                val b64 = Base64.getEncoder().encodeToString(out.toByteArray())
                if (b64.length <= NotifRules.MAX_ICON_BASE64) return b64
            } catch (_: Exception) { return null }
        }
        return null
    }
}
