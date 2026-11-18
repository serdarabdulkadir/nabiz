package com.nabiz.android.notif

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import com.nabiz.android.NabizApp

/** Sistem "Bildirim erisimi" ile baglanir; olaylari NotifHub'a iletir (suzme ve hiz siniri orada). */
class NotifListener : NotificationListenerService() {
    private val hub get() = (application as NabizApp).phone.notifs

    override fun onListenerConnected() = hub.onConnected(this)
    override fun onListenerDisconnected() = hub.onDisconnected(this)
    override fun onNotificationPosted(sbn: StatusBarNotification) = hub.onPosted(sbn)
    override fun onNotificationRemoved(sbn: StatusBarNotification) = hub.onRemoved(sbn)
}
