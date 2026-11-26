package com.nabiz.android.aktar

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.nabiz.android.R

/** Direct Share: eslesmis Mac, Paylas sayfasinda kisi gibi gorunur (res/xml/share_targets.xml ile eslesir). */
object AktarShortcuts {
    const val ID = "aktar_mac"
    const val CATEGORY = "com.nabiz.android.category.SHARE_MAC"

    fun publish(ctx: Context, macName: String) {
        try {
            val s = ShortcutInfoCompat.Builder(ctx, ID)
                .setShortLabel(macName)
                .setLongLabel(macName)
                .setIcon(IconCompat.createWithResource(ctx, R.drawable.ic_aktar_mac))
                .setIntent(Intent(ctx, ShareActivity::class.java).setAction(Intent.ACTION_SEND))
                .setCategories(setOf(CATEGORY))
                .setLongLived(true)
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(ctx, s)
        } catch (_: Exception) { }
    }

    fun remove(ctx: Context) {
        try { ShortcutManagerCompat.removeDynamicShortcuts(ctx, listOf(ID)) } catch (_: Exception) { }
    }
}
