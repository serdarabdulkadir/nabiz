package com.nabiz.android.service

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Mac kartinin bildirim tasarimi. */
enum class NotifStyle(val key: String, val label: String, val description: String) {
    CANLI("canli", "Canlı", "CPU ilerleme çubuğu"),
    UCLU("uclu", "Üçlü", "CPU, RAM ve Disk için üç ayrı çubuk"),
    KOMPAKT("kompakt", "Kompakt", "Tek satır, ilerleme çubuğu yok"),
    AYRINTILI("ayrintili", "Ayrıntılı", "Açılınca tüm satırlar"),
    PIL("pil", "Pil", "Mac pili ve kalan süre");

    companion object {
        fun fromKey(k: String?): NotifStyle = entries.firstOrNull { it.key == k } ?: CANLI
    }
}

/** Secilen tasarim SharedPreferences'ta; degisince akis yayar (bildirim hemen yeniden cizilir). */
class NotifSettings(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("nabiz_ui", Context.MODE_PRIVATE)
    private val _style = MutableStateFlow(NotifStyle.fromKey(prefs.getString("notif_style", null)))
    val style: StateFlow<NotifStyle> = _style.asStateFlow()

    fun set(s: NotifStyle) {
        prefs.edit().putString("notif_style", s.key).apply()
        _style.value = s
    }
}
