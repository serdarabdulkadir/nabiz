package com.nabiz.android.aktar

import android.app.Service
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat
import com.nabiz.android.NabizApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Aktar suresince calisan on plan servisi (dataSync). Yalniz aktarim varken yasar (dataSync suresi sinirli).
 * Gonderme istegi uri'leri ClipData + FLAG_GRANT_READ_URI_PERMISSION ile getirir: izin servis omru boyunca gecerlidir.
 */
class AktarService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as NabizApp
        app.aktar.start()
        val n = AktarNotifier.progress(this, app.aktar.transfers.value.firstOrNull { it.running }, app.aktar.transfers.value.count { it.running })
        if (Build.VERSION.SDK_INT >= 29) startForeground(AktarNotifier.ID_PROGRESS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(AktarNotifier.ID_PROGRESS, n)
        // Calisan aktarim kalmayinca (kisa bir bekleyisle) servis kapanir.
        scope.launch {
            app.aktar.transfers.collectLatest { list ->
                if (list.none { it.running }) {
                    delay(6_000)
                    stopSelf()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SEND) {
            val uris = ArrayList<Uri>()
            intent.clipData?.let { c -> for (i in 0 until c.itemCount) c.getItemAt(i).uri?.let { uris += it } }
            if (uris.isNotEmpty() && !(application as NabizApp).aktar.send(uris)) {
                android.widget.Toast.makeText(applicationContext, "Mac bağlı değil ya da Aktar kapalı", android.widget.Toast.LENGTH_SHORT).show()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val ACTION_SEND = "com.nabiz.android.AKTAR_GONDER"

        /** Aktarim icin servisi baslatir (arka planda izin verilmezse sessizce vazgecer; aktarim yine NabizService onceligiyle surer). */
        fun ensureRunning(ctx: Context) {
            try { ContextCompat.startForegroundService(ctx, Intent(ctx, AktarService::class.java)) } catch (_: Exception) { }
        }

        /** Secilen uri'leri Mac'e gonderir (on plandaki etkinlikten cagrilir). */
        fun send(ctx: Context, uris: List<Uri>) {
            if (uris.isEmpty()) return
            val clip = ClipData.newRawUri("aktar", uris[0])
            for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
            val i = Intent(ctx, AktarService::class.java).setAction(ACTION_SEND)
            i.clipData = clip
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try { ContextCompat.startForegroundService(ctx, i) } catch (_: Exception) { }
        }
    }
}
