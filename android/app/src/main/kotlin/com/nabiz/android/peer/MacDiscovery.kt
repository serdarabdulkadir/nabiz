package com.nabiz.android.peer

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.net.InetAddress

/** Bulunan Mac'in kaynagi: yerel ag (NSD/UDP), hotspot arayuzu (ap0 vb.) ya da kayitli son adres. */
enum class MacSource { LAN, HOTSPOT, LAST }

data class MacService(
    val serviceName: String, val id: String, val name: String, val host: InetAddress, val port: Int,
    val source: MacSource = MacSource.LAN,
    /** Son gorulme (epoch ms); 60 sn gorulmeyen listeden duser. */
    val lastSeen: Long = 0L,
)

/**
 * Mac kesfi: `_nabiz._tcp` Bonjour/NSD (TXT: ad, surum, id) + UDP yayin + kayitli son adres.
 * Sonuclar `id` ile birlestirilir; `restart` listeyi silmez, 60 sn gorulmeyen duser.
 */
@Suppress("DEPRECATION")
class MacDiscovery(context: Context) {
    private val appCtx = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var udpJob: Job? = null
    private var netCb: ConnectivityManager.NetworkCallback? = null
    private var netSignature: Set<String> = emptySet()
    /** Ag degisti (arayuz/adres degisimi, hotspot istemcisi): istemci geri cekilmeyi sifirlayip hemen dener. */
    @Volatile var onNetworkChanged: (() -> Unit)? = null

    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _found = MutableStateFlow<List<MacService>>(emptyList())
    val found: StateFlow<List<MacService>> = _found.asStateFlow()

    private val lock = Any()
    private var listener: NsdManager.DiscoveryListener? = null
    private val queue = ArrayDeque<NsdServiceInfo>()
    private var resolving = false

    private fun upsert(svc: MacService) {
        _found.update { DiscoveryMerge.prune(DiscoveryMerge.merge(it, svc), System.currentTimeMillis()) }
    }

    /** Kayitli son adres: listeye "Son adres" olarak girer, baglanti ilk onu dener. */
    fun injectLast(id: String, name: String, host: InetAddress, port: Int) =
        upsert(MacService("last:$id", id, name, host, port, MacSource.LAST, System.currentTimeMillis()))

    /** Bu id'nin tum kayitlarini kaldirir (baglanti denemesi basarisiz: bayat adres). */
    fun forget(id: String) { _found.update { l -> l.filterNot { it.id == id } } }

    fun dropLast(id: String) { _found.update { DiscoveryMerge.dropLast(it, id) } }

    /** Suresi dolanlari ayiklar (UDP dongusu her turda cagirir). */
    fun prune() { _found.update { DiscoveryMerge.prune(it, System.currentTimeMillis()) } }

    private fun checkNetwork() {
        val sig = localNets().map { it.ifName + "/" + it.ip.joinToString(".") { b -> (b.toInt() and 255).toString() } }.toSet()
        val changed = netSignature.isNotEmpty() && sig != netSignature
        netSignature = sig
        if (changed) onNetworkChanged?.invoke()
    }

    private fun startNetwork() {
        if (udpJob == null) {
            udpJob = UdpDiscovery({ System.currentTimeMillis() }, { upsert(it) }, { prune(); checkNetwork() }).launch(scope)
        }
        if (netCb == null) {
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { onNetworkChanged?.invoke() }
                override fun onLost(network: Network) { onNetworkChanged?.invoke() }
            }
            try {
                (appCtx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(cb)
                netCb = cb
            } catch (_: Exception) { }
        }
    }

    private fun stopNetwork() {
        udpJob?.cancel(); udpJob = null
        netCb?.let { try { (appCtx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) } catch (_: Exception) { } }
        netCb = null
    }

    fun start() {
        startNetwork()
        synchronized(lock) {
            if (listener != null) return
            val l = object : NsdManager.DiscoveryListener {
                override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {}
                override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {}
                override fun onDiscoveryStarted(serviceType: String?) {}
                override fun onDiscoveryStopped(serviceType: String?) {}
                override fun onServiceFound(info: NsdServiceInfo) {
                    if (!info.serviceType.startsWith("_nabiz._tcp")) return
                    synchronized(lock) { queue.addLast(info) }
                    pump()
                }
                // Kayip duyurusu listeyi bosaltmaz: 60 sn gorulmeyen kayit kendiliginden duser.
                override fun onServiceLost(info: NsdServiceInfo) {}
            }
            listener = l
            try {
                nsd.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, l)
            } catch (e: Exception) {
                listener = null
            }
        }
    }

    /** Kesfi bastan baslatir (NSD + UDP seri yeniden); bulunan Mac listesi korunur. */
    fun restart() {
        stopDiscovery()
        udpJob?.cancel(); udpJob = null   // ag geri cagrisi kalir (yeniden kaydi onAvailable'i tetikleyip dongu yapar)
        start()
    }

    /** Son bilinen hizmet adini yeniden cozumler (kesif duyurusunu beklemeden). */
    fun resolveKnown(serviceName: String) {
        val info = NsdServiceInfo().apply { this.serviceName = serviceName; serviceType = TYPE }
        synchronized(lock) { queue.addLast(info) }
        pump()
    }

    private fun stopDiscovery() {
        synchronized(lock) {
            val l = listener ?: return
            listener = null
            queue.clear()
            resolving = false
            try { nsd.stopServiceDiscovery(l) } catch (_: Exception) { }
        }
    }

    /** Tam durdurma: liste de silinir. */
    fun stop() {
        stopDiscovery()
        stopNetwork()
        _found.value = emptyList()
    }

    private fun pump() {
        val next: NsdServiceInfo
        synchronized(lock) {
            if (resolving || queue.isEmpty()) return
            resolving = true
            next = queue.removeFirst()
        }
        try {
            nsd.resolveService(next, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) { done() }
                override fun onServiceResolved(info: NsdServiceInfo) {
                    try { accept(info) } finally { done() }
                }
            })
        } catch (e: Exception) {
            done()
        }
    }

    private fun done() {
        synchronized(lock) { resolving = false }
        pump()
    }

    private fun accept(info: NsdServiceInfo) {
        fun txt(k: String): String? = info.attributes?.get(k)?.toString(Charsets.UTF_8)
        val id = txt("id") ?: return
        val host = info.host ?: return
        val hotspot = localNets().any { n -> UdpCodec.isHotspotName(n.ifName) && UdpCodec.broadcastOf(n.ip, n.prefix).contentEquals(UdpCodec.broadcastOf(host.address.takeIf { it.size == 4 } ?: return@any false, n.prefix)) }
        upsert(MacService(info.serviceName, id, txt("ad") ?: info.serviceName, host, info.port, if (hotspot) MacSource.HOTSPOT else MacSource.LAN, System.currentTimeMillis()))
    }

    private companion object {
        const val TYPE = "_nabiz._tcp."
    }
}
