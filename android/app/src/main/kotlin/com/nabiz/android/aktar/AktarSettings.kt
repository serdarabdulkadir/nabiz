package com.nabiz.android.aktar

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Ayarlar: "Aktar'i ac" (varsayilan ACIK) ve "Mac'ten otomatik kabul" (varsayilan KAPALI). */
class AktarSettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("nabiz_aktar", Context.MODE_PRIVATE)

    private val _enabled = MutableStateFlow(prefs.getBoolean(KEY_ENABLED, true))
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    private val _autoAccept = MutableStateFlow(prefs.getBoolean(KEY_AUTO, false))
    val autoAccept: StateFlow<Boolean> = _autoAccept.asStateFlow()

    fun setEnabled(on: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, on).apply()
        _enabled.value = on
    }

    fun setAutoAccept(on: Boolean) {
        prefs.edit().putBoolean(KEY_AUTO, on).apply()
        _autoAccept.value = on
    }

    private companion object {
        const val KEY_ENABLED = "aktar_acik"
        const val KEY_AUTO = "otomatik_kabul"
    }
}
