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

    fun unpair() = nabiz.client.unpair()
}
