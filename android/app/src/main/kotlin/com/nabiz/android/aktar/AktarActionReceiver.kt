package com.nabiz.android.aktar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.nabiz.android.NabizApp

/** Bildirimdeki Kabul et / Reddet / Iptal eylemleri. */
class AktarActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val aid = intent.getStringExtra(AktarNotifier.EXTRA_AID) ?: return
        val mgr = (context.applicationContext as NabizApp).aktar
        when (intent.action) {
            AktarNotifier.ACTION_ACCEPT -> { AktarService.ensureRunning(context); mgr.accept(aid) }
            AktarNotifier.ACTION_REJECT -> mgr.reject(aid)
            AktarNotifier.ACTION_CANCEL -> mgr.cancel(aid)
        }
    }
}
