package com.nabiz.android.stats

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.net.TrafficStats
import com.nabiz.android.peer.BatteryStats
import com.nabiz.android.peer.DiskStats
import com.nabiz.android.peer.MemStats
import com.nabiz.android.peer.NetStats
import com.nabiz.android.peer.Snapshot

/** Telefonun kendi olcumleri. CPU kullanimi Android 8+ okunamaz: cpu alani yazilmaz. Okunamayan alan null. */
class PhoneSampler(context: Context) {
    private val ctx = context.applicationContext
    private var prevTx = -1L
    private var prevRx = -1L
    private var prevAt = 0L

    @Synchronized
    fun sample(): Snapshot {
        val now = SystemClock.elapsedRealtime()
        return Snapshot(
            ts = System.currentTimeMillis() / 1000,
            mem = mem(),
            disk = disk(),
            battery = battery(),
            net = net(now),
            uptime = now / 1000,
            thermal = thermal(),
        )
    }

    private fun battery(): BatteryStats? {
        val i: Intent = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return null
        val level = StatsMath.batteryPercent(
            i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1), i.getIntExtra(BatteryManager.EXTRA_SCALE, -1),
        ) ?: return null
        val status = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val temp = StatsMath.tempC(i.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE))
        return BatteryStats(level = level, charging = charging, temp = temp)
    }

    private fun mem(): MemStats? = try {
        val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        if (mi.totalMem <= 0) null
        else MemStats(mi.totalMem - mi.availMem, mi.totalMem, StatsMath.memPressure(mi.availMem, mi.totalMem, mi.lowMemory))
    } catch (_: Exception) { null }

    private fun disk(): DiskStats? = try {
        val fs = StatFs(Environment.getDataDirectory().path)
        val total = fs.blockCountLong * fs.blockSizeLong
        val avail = fs.availableBlocksLong * fs.blockSizeLong
        if (total <= 0) null else DiskStats(total - avail, total)
    } catch (_: Exception) { null }

    private fun net(now: Long): NetStats? {
        val tx = TrafficStats.getTotalTxBytes()
        val rx = TrafficStats.getTotalRxBytes()
        val up = StatsMath.rate(prevTx, tx, now - prevAt)
        val down = StatsMath.rate(prevRx, rx, now - prevAt)
        prevTx = tx; prevRx = rx; prevAt = now
        return if (up == null || down == null) null else NetStats(up, down)
    }

    private fun thermal(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return StatsMath.thermal(pm.currentThermalStatus)
    }
}
