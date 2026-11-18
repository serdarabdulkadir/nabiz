package com.nabiz.android.phone

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Arama durumu ve eylemleri (ORBIO PhoneController'dan sadelestirildi: telefon bilgisi, arama bildirimi, arama/kisi listesi yok).
 * Yalniz `cagriYonetimi` anahtari aciksa durum izlenir; kisi adi icin ayrica `kisiler` anahtari gerekir.
 */
@SuppressLint("MissingPermission")
class PhoneController(context: Context, private val flags: () -> ShareFlags) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    private val _call = MutableStateFlow(CallInfo())
    val call: StateFlow<CallInfo> = _call.asStateFlow()

    private var monitorStarted = false
    private var pendingNumber: String? = null
    private var pendingDial: String? = null
    @Volatile private var dialedByApp = false
    private var keepModern: Any? = null
    private var keepLegacy: Any? = null
    private var numberReceiver: BroadcastReceiver? = null

    private fun has(p: String) = ContextCompat.checkSelfPermission(app, p) == PackageManager.PERMISSION_GRANTED

    fun hasCallPermissions() = has(Manifest.permission.READ_PHONE_STATE) &&
        has(Manifest.permission.ANSWER_PHONE_CALLS) && has(Manifest.permission.CALL_PHONE)

    /** Izin ve anahtar uygunsa dinleyiciyi kurar (bir kez); degisimde tekrar cagrilabilir. */
    @Synchronized
    fun ensureStarted() {
        if (!flags().cagriYonetimi) { _call.value = CallInfo(); return }
        startCallMonitorIfPossible()
        syncCurrentState()
    }

    /** Anahtar arama ortasinda acildiysa mevcut durum sistemden okunur (yon/numara bilinmez). */
    private fun syncCurrentState() {
        if (!monitorStarted || _call.value.durum != "bosta" || !has(Manifest.permission.READ_PHONE_STATE)) return
        val s = try { (app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager).callState } catch (_: Exception) { return }
        when (s) {
            TelephonyManager.CALL_STATE_RINGING -> handleState(s)
            TelephonyManager.CALL_STATE_OFFHOOK -> _call.value = CallInfo("acik", null, null, null, SystemClock.elapsedRealtime())
        }
    }

    /** Servis kapanirken: dinleyici ve alici kaldirilir. */
    @Synchronized
    fun stop() {
        numberReceiver?.let { try { app.unregisterReceiver(it) } catch (_: Exception) { } }
        numberReceiver = null
        val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) (keepModern as? TelephonyCallback)?.let { tm.unregisterTelephonyCallback(it) }
            else (keepLegacy as? PhoneStateListener)?.let { tm.listen(it, PhoneStateListener.LISTEN_NONE) }
        } catch (_: Exception) { }
        keepModern = null; keepLegacy = null
        monitorStarted = false
        _call.value = CallInfo()
    }

    @Suppress("DEPRECATION")
    @Synchronized
    private fun startCallMonitorIfPossible() {
        if (monitorStarted || !has(Manifest.permission.READ_PHONE_STATE)) return
        monitorStarted = true
        val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) registerModern(tm) else registerLegacy(tm)
            // Sistem yayini oldugu icin EXPORTED gerekir; numara yalniz "caliyor" yayininda ve dinleyici durumuyla tutarliysa kabul edilir.
            val r = object : BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) {
                    if (i.getStringExtra(TelephonyManager.EXTRA_STATE) != TelephonyManager.EXTRA_STATE_RINGING) return
                    val n = i.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
                    if (!n.isNullOrBlank()) onNumber(n)
                }
            }
            numberReceiver = r
            ContextCompat.registerReceiver(app, r, IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED), ContextCompat.RECEIVER_EXPORTED)
        } catch (_: Exception) {
            monitorStarted = false
        }
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun registerModern(tm: TelephonyManager) {
        val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) { handleState(state) }
        }
        keepModern = cb
        tm.registerTelephonyCallback(ContextCompat.getMainExecutor(app), cb)
    }

    @Suppress("DEPRECATION")
    private fun registerLegacy(tm: TelephonyManager) {
        main.post {
            val l = object : PhoneStateListener() {
                @Deprecated("Deprecated in Java")
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    if (!phoneNumber.isNullOrBlank()) pendingNumber = phoneNumber
                    handleState(state)
                }
            }
            keepLegacy = l
            tm.listen(l, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun onNumber(n: String) {
        if (!flags().cagriYonetimi) return
        val cur = _call.value
        // Bosta ya da giden aramadayken gelen numara kabul edilmez (bayat yayin); dinleyici henuz "caliyor" demediyse bekletilir.
        if (cur.durum == "bosta") { pendingNumber = n; return }
        if (cur.durum != "caliyor") return
        pendingNumber = n
        _call.value = cur.copy(numara = n, kisiAdi = lookupName(n) ?: cur.kisiAdi)
    }

    private fun handleState(state: Int) {
        if (!flags().cagriYonetimi) { _call.value = CallInfo(); return }
        val prev = _call.value
        val now = SystemClock.elapsedRealtime()
        _call.value = when (state) {
            TelephonyManager.CALL_STATE_RINGING ->
                CallInfo("caliyor", "gelen", pendingNumber, pendingNumber?.let { lookupName(it) })
            TelephonyManager.CALL_STATE_OFFHOOK -> when (prev.durum) {
                "caliyor" -> prev.copy(durum = "acik", startedAt = now)
                "acik", "araniyor" -> prev
                else -> CallInfo("araniyor", "giden", pendingDial, pendingDial?.let { lookupName(it) }, now)
            }
            else -> {
                pendingNumber = null; pendingDial = null; dialedByApp = false
                CallInfo()
            }
        }
    }

    /** Kisi adi yalniz `kisiler` anahtari acik ve izin verilmisse okunur. */
    private fun lookupName(number: String): String? {
        if (!flags().kisiler || !has(Manifest.permission.READ_CONTACTS)) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            app.contentResolver.query(uri, arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (_: Exception) { null }
    }

    // --- Eylemler (cagiran `cagriYonetimi` anahtarini once denetler) ---

    private fun telecom() = app.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    fun answer(): ActionResult {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) return ActionResult.NO_PERMISSION
        return try { telecom().acceptRingingCall(); ActionResult.OK } catch (_: Exception) { ActionResult.FAILED }
    }

    /** Calan aramayi reddeder ya da suren aramayi bitirir (TelecomManager.endCall, API 28+). */
    fun endCall(): ActionResult {
        if (!has(Manifest.permission.ANSWER_PHONE_CALLS)) return ActionResult.NO_PERMISSION
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return ActionResult.UNSUPPORTED
        return try {
            when {
                telecom().endCall() -> ActionResult.OK
                dialedByApp -> ActionResult.UNSUPPORTED
                else -> ActionResult.FAILED
            }
        } catch (_: Exception) { ActionResult.FAILED }
    }

    fun dial(raw: String): ActionResult {
        val number = normalizeDialNumber(raw) ?: return ActionResult.INVALID
        if (!has(Manifest.permission.CALL_PHONE)) return ActionResult.NO_PERMISSION
        return try {
            pendingDial = number
            dialedByApp = true
            telecom().placeCall(Uri.fromParts("tel", number, null), Bundle())
            ActionResult.OK
        } catch (_: Exception) {
            dialedByApp = false
            ActionResult.FAILED
        }
    }
}
