package com.nabiz.android.alerts

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.nabiz.android.MainActivity
import com.nabiz.android.R

/** Uyari bildirimleri: Mac kartindan ayri, yuksek onemli kanal. */
object AlertNotifier {
    const val CHANNEL = "uyarilar"
    const val EXTRA_TAB = "tab"
    private const val TEST_ID = 9000

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "Uyarılar", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Pil, depolama, işlemci ve bağlantı uyarıları"
        })
    }

    fun notify(ctx: Context, fire: AlertFire) =
        post(ctx, 1000 + fire.rule.ordinal * 2 + fire.subject.ordinal, fire.title, fire.text, if (fire.subject == Subject.MAC) 1 else 0)

    fun notifyTest(ctx: Context) = post(ctx, TEST_ID, "Nabız: Deneme bildirimi", "Uyarılar çalışıyor.", 0)

    private fun post(ctx: Context, id: Int, title: String, text: String, tab: Int) {
        ensureChannel(ctx)
        val pi = PendingIntent.getActivity(
            ctx, id,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra(EXTRA_TAB, tab),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_nabiz)
            .setContentTitle(title).setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try { NotificationManagerCompat.from(ctx).notify(id, n) } catch (_: SecurityException) { }
    }
}
