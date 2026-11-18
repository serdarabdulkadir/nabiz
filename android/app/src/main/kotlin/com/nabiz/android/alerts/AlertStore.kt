package com.nabiz.android.alerts

import android.content.Context

/** Uyari ayarlari ve durumu (docs/uyarilar.md anahtarlari). */
class AlertStore(context: Context) : AlertState {
    private val prefs = context.applicationContext.getSharedPreferences("nabiz_alerts", Context.MODE_PRIVATE)

    private fun k(r: AlertRule, s: Subject, f: String) = "alert.${r.id}.${s.key}.$f"

    fun config(r: AlertRule, s: Subject): RuleConfig {
        val d = r.defaults(s)
        return RuleConfig(
            on = prefs.getBoolean(k(r, s, "on"), d.on),
            esik = prefs.getInt(k(r, s, "esik"), d.esik),
            sureDk = prefs.getInt(k(r, s, "sureDk"), d.sureDk),
        )
    }

    fun setOn(r: AlertRule, s: Subject, v: Boolean) = prefs.edit().putBoolean(k(r, s, "on"), v).apply()
    fun setEsik(r: AlertRule, s: Subject, v: Int) = prefs.edit().putInt(k(r, s, "esik"), v).apply()
    fun setSureDk(r: AlertRule, s: Subject, v: Int) = prefs.edit().putInt(k(r, s, "sureDk"), v).apply()

    override fun son(rule: AlertRule, s: Subject): Long = prefs.getLong(k(rule, s, "son"), 0L)
    override fun setSon(rule: AlertRule, s: Subject, epochSec: Long) = prefs.edit().putLong(k(rule, s, "son"), epochSec).apply()
    override fun aktif(rule: AlertRule, s: Subject): Boolean = prefs.getBoolean(k(rule, s, "aktif"), false)
    override fun setAktif(rule: AlertRule, s: Subject, v: Boolean) {
        if (aktif(rule, s) != v) prefs.edit().putBoolean(k(rule, s, "aktif"), v).apply()
    }
}
