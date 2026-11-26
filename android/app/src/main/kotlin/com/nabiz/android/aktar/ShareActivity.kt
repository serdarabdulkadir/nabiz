package com.nabiz.android.aktar

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nabiz.android.NabizApp
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.service.NabizService
import com.nabiz.android.ui.ShareSheet
import com.nabiz.android.ui.theme.NabizTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Paylas hedefi (ACTION_SEND / SEND_MULTIPLE, her tur): yari saydam alt sayfa; Mac'e dokununca Aktar servisi gonderir. */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val uris = sharedUris(intent)
        if (uris.isEmpty()) { finish(); return }
        val direct = intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID) == AktarShortcuts.ID
        val app = application as NabizApp
        NabizService.start(this)
        setContent {
            NabizTheme {
                val link by app.client.state.collectAsStateWithLifecycle()
                val enabled by app.aktarSettings.enabled.collectAsStateWithLifecycle()
                var total by remember { mutableStateOf<Long?>(null) }
                var sending by remember { mutableStateOf(false) }
                val ready = link.phase == LinkPhase.READY
                LaunchedEffect(Unit) { total = withContext(Dispatchers.IO) { AktarFiles.totalSize(this@ShareActivity, uris) } }
                fun send() {
                    if (sending || !ready || !enabled) return
                    sending = true
                    AktarService.send(this@ShareActivity, uris)
                }
                // Direct Share (Mac kisayolu): baglanti hazir olunca ek dokunus olmadan gonder.
                LaunchedEffect(ready, enabled) { if (direct && ready && enabled) send() }
                LaunchedEffect(sending) { if (sending) { delay(700); finish() } }
                ShareSheet(
                    count = uris.size, totalBytes = total,
                    macName = link.macName ?: app.store.pinned.value?.name,
                    ready = ready, enabled = enabled, sending = sending,
                    onSend = ::send, onRetry = { app.client.rescan() }, onDismiss = { finish() },
                )
            }
        }
    }

    companion object {
        /** Paylasilan dosya uri'leri (ClipData once, yoksa EXTRA_STREAM). Duz metin paylasimi bos doner. */
        fun sharedUris(i: Intent): List<Uri> {
            val out = LinkedHashSet<Uri>()
            i.clipData?.let { c -> for (n in 0 until c.itemCount) c.getItemAt(n).uri?.let { out += it } }
            if (out.isEmpty()) {
                if (i.action == Intent.ACTION_SEND_MULTIPLE) {
                    val l = if (Build.VERSION.SDK_INT >= 33) i.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    else @Suppress("DEPRECATION") i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    l?.let { out += it }
                } else {
                    val u = if (Build.VERSION.SDK_INT >= 33) i.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                    else @Suppress("DEPRECATION") i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                    u?.let { out += it }
                }
            }
            return out.toList()
        }
    }
}
