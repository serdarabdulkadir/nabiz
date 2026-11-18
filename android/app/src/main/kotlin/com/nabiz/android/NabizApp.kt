package com.nabiz.android

import android.app.Application
import android.os.Build
import com.nabiz.android.alerts.AlertStore
import com.nabiz.android.peer.MacDiscovery
import com.nabiz.android.peer.NabizClient
import com.nabiz.android.peer.PeerStore
import com.nabiz.android.service.NotifSettings
import com.nabiz.android.stats.PhoneSampler

/** Servis ve arayuzun paylastigi tek kanal nesnesi. */
class NabizApp : Application() {
    val store by lazy { PeerStore(this) }
    val notif by lazy { NotifSettings(this) }
    val sampler by lazy { PhoneSampler(this) }
    val alerts by lazy { AlertStore(this) }
    val history by lazy { com.nabiz.android.stats.HistoryStore() }
    /** Gorunen ad: kullanicinin telefona verdigi ad (Ayarlar > Telefon hakkinda); yoksa model. */
    val deviceName: String by lazy {
        try { android.provider.Settings.Global.getString(contentResolver, android.provider.Settings.Global.DEVICE_NAME) } catch (_: Exception) { null }
            ?.takeIf { it.isNotBlank() } ?: Build.MODEL
    }
    val client by lazy {
        val version = try { packageManager.getPackageInfo(packageName, 0).versionName ?: "0" } catch (_: Exception) { "0" }
        NabizClient(store, MacDiscovery(this), deviceName, Build.MODEL, version) { sampler.sample() }
    }
}
