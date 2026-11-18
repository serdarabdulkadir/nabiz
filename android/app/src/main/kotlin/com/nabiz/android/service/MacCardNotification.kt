package com.nabiz.android.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import androidx.core.app.NotificationCompat
import com.nabiz.android.MainActivity
import com.nabiz.android.R

/**
 * Mac karti = servisin kalici bildirimi. API 36+: Notification.ProgressStyle (Live Update, promoted ongoing),
 * altinda: NotificationCompat BigTextStyle + setProgress.
 */
object MacCardNotification {
    const val CHANNEL = "mac_card"
    const val ID = 1
    const val ACTION_CMD = "com.nabiz.android.CMD"
    const val EXTRA_EYLEM = "eylem"

    private const val C_NORMAL = 0xFF7A8190.toInt()
    private const val C_WARN = 0xFFE0A100.toInt()
    private const val C_CRIT = 0xFFD70015.toInt()
    private const val C_GOOD = 0xFF2E9E57.toInt()
    private const val C_TRACK = 0x40808080

    fun toneColor(t: Tone): Int = when (t) {
        Tone.NORMAL -> C_NORMAL
        Tone.WARN -> C_WARN
        Tone.CRIT -> C_CRIT
        Tone.GOOD -> C_GOOD
        Tone.TRACK -> C_TRACK
    }

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Mac kartı", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Mac'in anlık durumu"
                setShowBadge(false)
            },
        )
    }

    fun build(ctx: Context, m: MacCardModel): Notification =
        if (Build.VERSION.SDK_INT >= 36) buildProgressStyle(ctx, m) else buildCompat(ctx, m)

    private fun contentIntent(ctx: Context): PendingIntent = PendingIntent.getActivity(
        ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun actionIntent(ctx: Context, eylem: String): PendingIntent = PendingIntent.getService(
        ctx, eylem.hashCode(),
        Intent(ctx, NabizService::class.java).setAction(ACTION_CMD).putExtra(EXTRA_EYLEM, eylem),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun smallIcon(m: MacCardModel) = if (m.charging) R.drawable.ic_stat_nabiz_charging else R.drawable.ic_stat_nabiz

    private fun actionIcon(eylem: String): Int = when (eylem) {
        "yenile" -> R.drawable.ic_act_refresh
        "kilitle" -> R.drawable.ic_act_lock
        "uyut" -> R.drawable.ic_act_moon
        "uyandir" -> R.drawable.ic_act_sun
        else -> R.drawable.ic_stat_nabiz
    }

    private fun buildCompat(ctx: Context, m: MacCardModel): Notification {
        val b = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(smallIcon(m))
            .setContentTitle(m.title)
            .setContentText(m.text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(m.bigText ?: m.text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(ctx))
        m.subText?.let { b.setSubText(it) }
        if (m.compatProgress != null) b.setProgress(100, m.compatProgress, false)
        m.actions.take(3).forEach { b.addAction(actionIcon(it.eylem), it.label, actionIntent(ctx, it.eylem)) }
        return b.build()
    }

    private fun buildProgressStyle(ctx: Context, m: MacCardModel): Notification {
        val b = Notification.Builder(ctx, CHANNEL)
            .setSmallIcon(smallIcon(m))
            .setContentTitle(m.title)
            .setContentText(m.text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setContentIntent(contentIntent(ctx))
        m.subText?.let { b.setSubText(it) }
        if (m.progress != null && m.segments.isNotEmpty()) {
            // setColorized KULLANILMAZ: terfiyi (promoted ongoing) engeller.
            val ps = Notification.ProgressStyle()
                .setStyledByProgress(true)
                .setProgressSegments(m.segments.map { Notification.ProgressStyle.Segment(it.length).setColor(toneColor(it.tone)) })
                .setProgressPoints(m.points.filter { it.at in 1 until m.progressMax }.map { Notification.ProgressStyle.Point(it.at).setColor(toneColor(it.tone)) })
                .setProgress(m.progress)
                .setProgressTrackerIcon(Icon.createWithResource(ctx, if (m.charging) R.drawable.ic_bolt else R.drawable.ic_tracker_dot))
            b.setStyle(ps)
        } else if (m.bigText != null) {
            b.setStyle(Notification.BigTextStyle().bigText(m.bigText))
        }
        m.shortCritical?.let { b.setShortCriticalText(it) }
        requestPromoted(b)
        m.actions.take(3).forEach {
            b.addAction(Notification.Action.Builder(Icon.createWithResource(ctx, actionIcon(it.eylem)), it.label, actionIntent(ctx, it.eylem)).build())
        }
        return b.build()
    }

    /** API 36.1'de Builder.setRequestPromotedOngoing var; 36.0 jar'inda yok, bu yuzden ekstra anahtar (gizli API yansimasi Android 16da engelli). */
    private fun requestPromoted(b: Notification.Builder) {
        b.addExtras(android.os.Bundle().apply { putBoolean("android.requestPromotedOngoing", true) })
    }
}
