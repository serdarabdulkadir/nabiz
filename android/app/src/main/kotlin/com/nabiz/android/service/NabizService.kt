package com.nabiz.android.service

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.nabiz.android.NabizApp
import com.nabiz.android.alerts.AlertEngine
import com.nabiz.android.alerts.AlertNotifier
import com.nabiz.android.alerts.Subject
import com.nabiz.android.peer.LinkReason
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.NabizClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** On plan servisi (connectedDevice): Mac baglantisini tutar, kendi stats'ini yollar, Mac kartini gunceller. */
class NabizService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var client: NabizClient
    private var multicast: WifiManager.MulticastLock? = null
    private var screenReceiver: BroadcastReceiver? = null
    private lateinit var engine: AlertEngine

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as NabizApp
        client = app.client
        engine = AlertEngine({ r, sub -> app.alerts.config(r, sub) }, app.alerts)
        AlertNotifier.ensureChannel(this)
        MacCardNotification.ensureChannel(this)
        val first = MacCardNotification.build(this, MacCardModel.from(client.state.value, app.notif.style.value))
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(MacCardNotification.ID, first, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(MacCardNotification.ID, first)
        }

        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicast = wifi.createMulticastLock("nabiz-mdns").apply { setReferenceCounted(false); acquire() }

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        client.requestSub(if (pm.isInteractive) SUB_ON else SUB_OFF)
        screenReceiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, i: Intent) {
                client.requestSub(if (i.action == Intent.ACTION_SCREEN_OFF) SUB_OFF else SUB_ON)
            }
        }.also {
            ContextCompat.registerReceiver(
                this, it,
                IntentFilter().apply { addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_SCREEN_OFF) },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        }
        client.start(scope)

        // Mac karti: degisim yoksa guncelleme yok, en cok saniyede bir.
        scope.launch {
            combine(client.state, (application as NabizApp).notif.style) { st, style -> MacCardModel.from(st, style) }.distinctUntilChanged().conflate().collect { m ->
                try {
                    NotificationManagerCompat.from(this@NabizService).notify(MacCardNotification.ID, MacCardNotification.build(this@NabizService, m))
                } catch (_: SecurityException) { }
                try {
                    android.service.quicksettings.TileService.requestListeningState(this@NabizService, android.content.ComponentName(this@NabizService, NabizTileService::class.java))
                } catch (_: Exception) { }
                delay(1000)
            }
        }
        // Telefonun kendi stats'i, Mac'in istedigi aralikla.
        scope.launch(Dispatchers.Default) {
            client.peerInterval.collectLatest { sec ->
                phoneAlerts()
                while (true) {
                    delay(sec * 1000L)
                    val snap = (application as NabizApp).sampler.sample()
                    (application as NabizApp).history.addPhone(System.currentTimeMillis(), snap)
                    if (client.state.value.phase == LinkPhase.READY) client.sendStats(snap)
                    phoneAlerts(snap)
                }
            }
        }
        // Mac uyarilari: her yeni Mac stats'inda; baglanti_koptu icin 30 sn'de bir.
        scope.launch {
            client.state.distinctUntilChangedBy { it.macSnapAt }.collect { st ->
                val snap = st.macSnap
                if (st.phase == LinkPhase.READY && snap != null) {
                    (application as NabizApp).history.addMac(st.macSnapAt, snap)
                    fire(engine.evaluate(Subject.MAC, snap, System.currentTimeMillis(), st.macSnapAt, macName(st)))
                }
            }
        }
        scope.launch {
            while (true) {
                delay(30_000)
                val st = client.state.value
                fire(engine.evaluateLink(System.currentTimeMillis(), st.lastSeenAt, st.phase == LinkPhase.READY, st.reason == LinkReason.SLEEPING, macName(st)))
            }
        }
        scope.launch {
            client.results.collect { r ->
                val ad = when (r.eylem) { "yenile" -> "Yenile"; "kilitle" -> "Kilitle"; "uyut" -> "Uyut"; "uyandir" -> "Uyandır"; else -> r.eylem }
                val sonuc = when (r.sonuc) { "tamam" -> "tamam"; "kapali" -> "Mac'te kapalı"; else -> "hata" }
                Toast.makeText(applicationContext, "$ad: $sonuc", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun macName(st: com.nabiz.android.peer.LinkState): String =
        st.macName ?: (application as NabizApp).store.pinned.value?.name?.takeIf { it.isNotBlank() } ?: "Mac"

    private fun fire(list: List<com.nabiz.android.alerts.AlertFire>) = list.forEach { AlertNotifier.notify(this, it) }

    private fun phoneAlerts(snap: com.nabiz.android.peer.Snapshot = (application as NabizApp).sampler.sample()) {
        val now = System.currentTimeMillis()
        fire(engine.evaluate(Subject.TELEFON, snap, now, now, (application as NabizApp).deviceName))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == MacCardNotification.ACTION_CMD) {
            intent.getStringExtra(MacCardNotification.EXTRA_EYLEM)?.let { client.sendCmd(it) }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        screenReceiver?.let { unregisterReceiver(it) }
        multicast?.let { if (it.isHeld) it.release() }
        client.stop()
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val SUB_ON = 2
        const val SUB_OFF = 10

        fun start(ctx: Context) {
            try {
                ContextCompat.startForegroundService(ctx, Intent(ctx, NabizService::class.java))
            } catch (_: Exception) { }
        }
    }
}
