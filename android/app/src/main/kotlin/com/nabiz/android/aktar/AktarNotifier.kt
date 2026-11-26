package com.nabiz.android.aktar

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.nabiz.android.MainActivity
import com.nabiz.android.R
import com.nabiz.android.alerts.AlertNotifier

/** Aktar bildirimleri: gelen teklif (Kabul et / Reddet), ilerleme (tek kalici bildirim), sonuc. */
object AktarNotifier {
    const val CH_OFFER = "aktar_teklif"
    const val CH_PROGRESS = "aktar_ilerleme"
    const val ID_PROGRESS = 7001
    const val ACTION_ACCEPT = "com.nabiz.android.AKTAR_KABUL"
    const val ACTION_REJECT = "com.nabiz.android.AKTAR_RED"
    const val ACTION_CANCEL = "com.nabiz.android.AKTAR_IPTAL"
    const val EXTRA_AID = "aid"

    fun offerId(aid: String): Int = 7100 + (aid.hashCode() and 0xFFFF)
    fun resultId(aid: String): Int = 80000 + (aid.hashCode() and 0xFFFF)

    fun ensureChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CH_OFFER) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_OFFER, "Aktar teklifleri", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Mac'ten gelen dosya teklifleri"
            })
        }
        if (nm.getNotificationChannel(CH_PROGRESS) == null) {
            nm.createNotificationChannel(NotificationChannel(CH_PROGRESS, "Aktar ilerlemesi", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Sürmekte olan dosya aktarımları"
                setShowBadge(false)
            })
        }
    }

    private fun openApp(ctx: Context, code: Int): PendingIntent = PendingIntent.getActivity(
        ctx, code,
        Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra(AlertNotifier.EXTRA_TAB, 2),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun action(ctx: Context, aid: String, act: String, code: Int): PendingIntent = PendingIntent.getBroadcast(
        ctx, code,
        Intent(ctx, AktarActionReceiver::class.java).setAction(act).putExtra(EXTRA_AID, aid),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun offer(ctx: Context, t: TransferInfo): Notification {
        ensureChannels(ctx)
        val id = offerId(t.aid)
        return NotificationCompat.Builder(ctx, CH_OFFER)
            .setSmallIcon(R.drawable.ic_stat_nabiz)
            .setContentTitle(AktarText.offerTitle(t.peer, t.files.size))
            .setContentText(AktarText.offerBody(t.files))
            .setStyle(NotificationCompat.BigTextStyle().bigText(AktarText.offerBody(t.files)))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(openApp(ctx, id))
            .setAutoCancel(false)
            .setTimeoutAfter(125_000)   // Mac 2 dk sonra zaten iptal eder
            .addAction(0, "Kabul et", action(ctx, t.aid, ACTION_ACCEPT, id + 1))
            .addAction(0, "Reddet", action(ctx, t.aid, ACTION_REJECT, id + 2))
            .build()
    }

    /** `t` null: servis acilirken yer tutucu. */
    fun progress(ctx: Context, t: TransferInfo?, running: Int): Notification {
        ensureChannels(ctx)
        val b = NotificationCompat.Builder(ctx, CH_PROGRESS)
            .setSmallIcon(R.drawable.ic_stat_nabiz)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(openApp(ctx, ID_PROGRESS))
        if (t == null) return b.setContentTitle("Aktar hazırlanıyor").setProgress(0, 0, true).build()
        val extra = if (running > 1) " (+${running - 1})" else ""
        b.setContentTitle(AktarText.progressTitle(t) + extra)
        when (t.status) {
            TransferStatus.ACTIVE -> b.setContentText(AktarText.subtitle(t)).setProgress(100, t.percent, false)
            else -> b.setContentText(AktarText.statusLabel(t.status)).setProgress(0, 0, true)
        }
        b.addAction(0, "İptal", action(ctx, t.aid, ACTION_CANCEL, ID_PROGRESS))
        return b.build()
    }

    fun result(ctx: Context, t: TransferInfo): Notification {
        ensureChannels(ctx)
        val title = AktarText.resultTitle(t)
        return NotificationCompat.Builder(ctx, CH_PROGRESS)
            .setSmallIcon(R.drawable.ic_stat_nabiz)
            .setContentTitle(title)
            .setContentText(AktarText.subtitle(t))
            .setAutoCancel(true)
            .setSilent(true)
            .setContentIntent(openApp(ctx, resultId(t.aid)))
            .build()
    }
}
