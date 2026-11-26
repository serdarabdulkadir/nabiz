package com.nabiz.android.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nabiz.android.peer.RemoteAddress
import com.nabiz.android.service.NotifStyle
import kotlinx.coroutines.launch
import com.nabiz.android.NabizApp
import com.nabiz.android.peer.LinkState
import com.nabiz.android.peer.PinnedMac
import com.nabiz.android.peer.Snapshot
import com.nabiz.android.stats.PhoneSampler
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val nabiz = app as NabizApp
    // Arayuzun kendi ornegi: servisin net oranini bozmasin.
    private val sampler = PhoneSampler(app)

    val link: StateFlow<LinkState> = nabiz.client.state
    val history get() = nabiz.history
    val pinned: StateFlow<PinnedMac?> = nabiz.store.pinned

    private val _phone = MutableStateFlow<Snapshot?>(null)
    val phone: StateFlow<Snapshot?> = _phone.asStateFlow()

    fun refreshPhone() { _phone.value = sampler.sample() }
    fun confirmSas(ok: Boolean) = nabiz.client.confirmSas(ok)
    fun sendCmd(eylem: String) = nabiz.client.sendCmd(eylem)
    val notifStyle: StateFlow<NotifStyle> = nabiz.notif.style
    fun setNotifStyle(s: NotifStyle) = nabiz.notif.set(s)

    fun remoteAddress(): String = nabiz.store.remoteAddress.orEmpty()
    fun saveRemoteAddress(a: String) { nabiz.store.remoteAddress = a }
    /** TCP baglanti denemesi; sonuc ana iplikte. */
    fun testRemote(a: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch { onResult(RemoteAddress.probe(a)) }
    }

    val alerts get() = nabiz.alerts
    fun testAlert() = com.nabiz.android.alerts.AlertNotifier.notifyTest(getApplication())

    val shareFlags get() = nabiz.phone.share.flags
    val systemGrants get() = nabiz.phone.systemGrants
    fun setShare(key: com.nabiz.android.phone.ShareKey, on: Boolean) = nabiz.phone.setShare(key, on)
    fun refreshShare() = nabiz.phone.refresh()

    val ai get() = nabiz.client.ai
    private val _aiSyncing = MutableStateFlow(false)
    /** ai.sync yollandi, yanit (ai.state) bekleniyor; en cok 10 sn. */
    val aiSyncing: StateFlow<Boolean> = _aiSyncing.asStateFlow()
    private var aiSyncJob: kotlinx.coroutines.Job? = null
    init { viewModelScope.launch { nabiz.client.aiAt.collect { _aiSyncing.value = false } } }
    fun aiSync(force: Boolean) {
        nabiz.client.aiSync(force)
        _aiSyncing.value = true
        aiSyncJob?.cancel()
        aiSyncJob = viewModelScope.launch { kotlinx.coroutines.delay(10_000); _aiSyncing.value = false }
    }
    val found get() = nabiz.client.found
    fun connectTo(id: String) = nabiz.client.connectTo(id)
    fun rescan() = nabiz.client.rescan()

    fun unpair() = nabiz.client.unpair()

    val transfers get() = nabiz.aktar.transfers
    val aktarEnabled get() = nabiz.aktarSettings.enabled
    val aktarAuto get() = nabiz.aktarSettings.autoAccept
    fun setAktarEnabled(on: Boolean) = nabiz.aktarSettings.setEnabled(on)
    fun setAktarAuto(on: Boolean) = nabiz.aktarSettings.setAutoAccept(on)
    fun aktarCancel(aid: String) = nabiz.aktar.cancel(aid)
    fun aktarAccept(aid: String) = nabiz.aktar.accept(aid)
    fun aktarReject(aid: String) = nabiz.aktar.reject(aid)
}
