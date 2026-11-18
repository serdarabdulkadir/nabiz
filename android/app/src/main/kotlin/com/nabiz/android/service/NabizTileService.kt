package com.nabiz.android.service

import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.nabiz.android.NabizApp
import com.nabiz.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** "Nabız · Mac" kutucugu: durum mevcut istemci state'inden okunur; dokununca Mac'e `yenile`, uzun basinca uygulama acilir. */
class NabizTileService : TileService() {
    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        val client = (application as NabizApp).client
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { sc ->
            sc.launch { client.state.map { TileModel.from(it) }.distinctUntilChanged().collect { render(it) } }
        }
    }

    override fun onStopListening() {
        scope?.cancel(); scope = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        (application as NabizApp).client.sendCmd("yenile")
    }

    private fun render(m: TileModel) {
        val t = qsTile ?: return
        t.label = "Nabız · Mac"
        t.icon = Icon.createWithResource(this, R.drawable.ic_stat_nabiz)
        t.state = if (m.active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = m.subtitle
        t.updateTile()
    }
}
