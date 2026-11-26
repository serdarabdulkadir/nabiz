package com.nabiz.android.aktar

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.core.app.NotificationManagerCompat
import com.nabiz.android.peer.AktarControl
import com.nabiz.android.peer.AktarCrypto
import com.nabiz.android.peer.AktarFile
import com.nabiz.android.peer.AktarFrameReader
import com.nabiz.android.peer.AktarReceiver
import com.nabiz.android.peer.AktarRole
import com.nabiz.android.peer.AktarSecureChannel
import com.nabiz.android.peer.AktarSender
import com.nabiz.android.peer.AktarSpace
import com.nabiz.android.peer.NabizClient
import com.nabiz.android.peer.PeerMessage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.io.BufferedInputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Aktar yoneticisi (docs/protokol.md bolum 13): kontrol mesajlarini isler, veri baglantisini (telefon -> Mac:47823) yonetir,
 * durumu `transfers` ile arayuze, bildirimlere ve ilerleme bildirimine verir. Dosya IO'su IO dispatcher'inda, akisla (bellek sismez).
 */
class AktarManager(
    private val ctx: Context,
    private val client: NabizClient,
    private val settings: AktarSettings,
    private val storage: AndroidAktarStorage,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val started = AtomicBoolean(false)
    private val _transfers = MutableStateFlow<List<TransferInfo>>(emptyList())
    /** Yeni olan basta; en cok 30 kayit (bellekte, uygulama oturumu boyunca). */
    val transfers: StateFlow<List<TransferInfo>> = _transfers.asStateFlow()

    private class Run(val aid: String, val dir: TransferDir) {
        @Volatile var cancelled = false
        @Volatile var socket: Socket? = null
        @Volatile var port: Int? = null
        @Volatile var receiver: AktarReceiver? = null
        @Volatile var sender: AktarSender? = null
        @Volatile var bitti: PeerMessage.AktarBitti? = null
        var uris: Map<Int, Uri> = emptyMap()
        val reply = CompletableDeferred<PeerMessage.AktarYanit>()
        val sent = ConcurrentHashMap<Int, Long>()
        val meter = SpeedMeter()
        @Volatile var lastUi = 0L
    }

    private val runs = ConcurrentHashMap<String, Run>()

    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch { client.aktar.collect { m -> try { onControl(m) } catch (e: Exception) { android.util.Log.w("NabizAktar", "kontrol hatasi", e) } } }
        scope.launch { watchNotifications() }
    }

    val hasRunning: Boolean get() = _transfers.value.any { it.running }

    // --- Arayuz eylemleri ---------------------------------------------------------------------------------------

    /** Mac'e gonderir. Baglanti yoksa ya da Aktar kapaliysa false. Dosya bilgisi IO'da okunur; uri'lerin okuma izni cagiran tarafta (servis) yasamalidir. */
    fun send(uris: List<Uri>): Boolean {
        val link = client.aktarLink
        if (!settings.enabled.value || link == null || uris.isEmpty()) return false
        scope.launch {
            val files = ArrayList<AktarFile>()
            val map = HashMap<Int, Uri>()
            for (u in uris) {
                val f = AktarFiles.describe(ctx, u, files.size) ?: continue
                map[f.fid] = u
                files += f
            }
            if (files.isEmpty()) { toast("Dosya okunamadı"); return@launch }
            val aid = UUID.randomUUID().toString()
            val run = Run(aid, TransferDir.OUT).also { it.uris = map }
            runs[aid] = run
            add(TransferInfo(aid, TransferDir.OUT, link.macName.ifBlank { "Mac" }, files, TransferStatus.WAITING, startedAt = System.currentTimeMillis()))
            client.send(PeerMessage.AktarTeklif(aid, files, files.sumOf { it.boyut }))
            val reply = withTimeoutOrNull(120_000) { run.reply.await() }
            when {
                run.cancelled -> return@launch
                reply == null -> {
                    client.send(PeerMessage.AktarIptal(aid))
                    end(aid, TransferStatus.CANCELLED, "Yanıt gelmedi")
                }
                !reply.kabul -> end(aid, TransferStatus.REJECTED, AktarText.rejectReason(reply.neden))
                else -> {
                    run.port = reply.port
                    update(aid) { it.copy(status = TransferStatus.CONNECTING) }
                    dataLoop(run, files, AktarRole.SENDER)
                }
            }
        }
        return true
    }

    fun accept(aid: String) {
        val run = runs[aid] ?: return
        val t = find(aid) ?: return
        if (t.status != TransferStatus.OFFERED) return
        update(aid) { it.copy(status = TransferStatus.CONNECTING, startedAt = System.currentTimeMillis()) }
        client.send(PeerMessage.AktarYanit(aid, true))
        scope.launch { dataLoop(run, t.files, AktarRole.RECEIVER) }
    }

    fun reject(aid: String) {
        val t = find(aid) ?: return
        if (t.status != TransferStatus.OFFERED) return
        client.send(PeerMessage.AktarYanit(aid, false, "reddedildi"))
        end(aid, TransferStatus.REJECTED, null)
    }

    /** Kullanici vazgecti (calisan ya da bekleyen aktarim). */
    fun cancel(aid: String) {
        val run = runs[aid] ?: return
        val t = find(aid) ?: return
        if (t.status == TransferStatus.OFFERED) { reject(aid); return }
        if (!t.running) return
        client.send(PeerMessage.AktarIptal(aid))
        run.cancelled = true
        closeSocket(run)
        run.receiver?.abort()
        end(aid, TransferStatus.CANCELLED, null)
    }

    // --- Kontrol mesajlari --------------------------------------------------------------------------------------

    private fun onControl(m: PeerMessage) {
        when (m) {
            is PeerMessage.AktarTeklif -> onOffer(m)
            is PeerMessage.AktarYanit -> runs[m.aid]?.let { if (it.dir == TransferDir.OUT) it.reply.complete(m) }
            is PeerMessage.AktarIptal -> runs[m.aid]?.let { r ->
                if (find(m.aid)?.running == true || find(m.aid)?.status == TransferStatus.OFFERED) {
                    r.cancelled = true
                    closeSocket(r)
                    r.receiver?.abort()
                    r.reply.cancel()
                    end(m.aid, TransferStatus.CANCELLED, "Mac iptal etti")
                }
            }
            is PeerMessage.AktarBitti -> runs[m.aid]?.let { r ->
                if (r.dir != TransferDir.OUT) return@let
                r.bitti = m
                r.sender?.complete()
                if (m.sonuc == "tamam") {
                    update(m.aid) { it.copy(doneBytes = it.totalBytes) }
                    end(m.aid, TransferStatus.DONE, null)
                } else end(m.aid, TransferStatus.FAILED, "${m.hatali.size} dosya doğrulanamadı")
            }
            else -> {}
        }
    }

    private fun onOffer(m: PeerMessage.AktarTeklif) {
        if (runs.containsKey(m.aid)) return
        if (!settings.enabled.value) { client.send(PeerMessage.AktarYanit(m.aid, false, "kapali")); return }
        if (!AktarSpace.enough(m.toplam, storage.freeBytes())) { client.send(PeerMessage.AktarYanit(m.aid, false, "yer_yok")); return }
        val run = Run(m.aid, TransferDir.IN).also { it.port = m.port }
        runs[m.aid] = run
        val peer = client.aktarLink?.macName?.takeIf { it.isNotBlank() } ?: client.state.value.macName ?: "Mac"
        add(TransferInfo(m.aid, TransferDir.IN, peer, m.dosyalar, TransferStatus.OFFERED, startedAt = System.currentTimeMillis()))
        if (settings.autoAccept.value) {
            AktarService.ensureRunning(ctx)
            accept(m.aid)
        }
    }

    // --- Veri baglantisi ----------------------------------------------------------------------------------------

    /** Iptal edildi ya da bitti (durum artik calisan degil). */
    private fun isOver(run: Run) = run.cancelled || find(run.aid)?.running != true

    private fun closeSocket(run: Run) { try { run.socket?.close() } catch (_: Exception) { } }

    /** Kopmada 10 dk icinde ayni `aid` ile yeniden baglanir (devam). */
    private suspend fun dataLoop(run: Run, files: List<AktarFile>, role: AktarRole) {
        val deadline = System.nanoTime() + 10L * 60 * 1_000_000_000
        var tries = 0
        if (role == AktarRole.RECEIVER) {
            run.receiver = AktarReceiver(run.aid, files, storage, onProgress = { _, _ -> progressIn(run) })
        }
        var failure: String? = null
        while (!isOver(run) && System.nanoTime() < deadline && tries < 8) {
            val link = client.aktarLink
            if (link == null) { failure = "Mac bağlı değil"; delay(1500); continue }
            try {
                if (connectOnce(run, files, role, link)) return
                failure = "Bağlantı koptu"
            } catch (e: Exception) {
                if (isOver(run)) return
                android.util.Log.w("NabizAktar", "veri baglantisi hatasi", e)
                failure = "Bağlantı koptu"
            } finally {
                run.receiver?.connectionLost()
                closeSocket(run)
            }
            if (isOver(run)) return
            tries++
            update(run.aid) { it.copy(status = TransferStatus.CONNECTING, speedBps = 0) }
            delay(2000)
        }
        if (isOver(run)) return
        run.receiver?.abort()
        client.send(PeerMessage.AktarIptal(run.aid))
        end(run.aid, TransferStatus.FAILED, failure ?: "Bağlantı kurulamadı")
    }

    /** Tek baglanti denemesi; aktarim tamamlandiysa true. */
    private fun connectOnce(run: Run, files: List<AktarFile>, role: AktarRole, link: com.nabiz.android.peer.AktarLink): Boolean {
        val s = Socket()
        run.socket = s
        s.tcpNoDelay = false          // veri kanali: toplu yazim
        s.keepAlive = true
        try { s.sendBufferSize = 1 shl 20; s.receiveBufferSize = 1 shl 20 } catch (_: Exception) { }
        s.connect(InetSocketAddress(link.host, run.port ?: DATA_PORT), 5_000)
        s.soTimeout = 60_000
        if (run.cancelled) return false
        val out = s.getOutputStream()
        val ins = BufferedInputStream(s.getInputStream(), 64 * 1024)
        AktarFrameReader.writePlain(out, com.nabiz.android.peer.AktarControlCodec.encode(AktarControl.Baglan(run.aid)).toByteArray(Charsets.UTF_8))
        val keys = AktarCrypto.deriveKeys(link.okm, run.aid)
        val (w, r) = AktarCrypto.keysFor(role, keys)
        val ch = AktarSecureChannel(ins, out, w, r)
        update(run.aid) { it.copy(status = TransferStatus.ACTIVE) }
        return if (role == AktarRole.RECEIVER) {
            val rc = run.receiver!!
            val done = rc.serve(ch)
            if (done) {
                client.send(rc.result())
                update(run.aid) { it.copy(doneBytes = it.totalBytes) }
                if (rc.failedFids.isEmpty()) end(run.aid, TransferStatus.DONE, null)
                else end(run.aid, TransferStatus.FAILED, "${rc.failedFids.size} dosya doğrulanamadı")
            }
            done
        } else {
            val sender = AktarSender(
                files,
                open = { f -> ctx.contentResolver.openInputStream(run.uris[f.fid]!!) ?: throw java.io.IOException("dosya açılamadı: ${f.ad}") },
                onProgress = { fid, sent -> progressOut(run, fid, sent) },
                isCancelled = { run.cancelled },
            )
            run.sender = sender
            if (run.bitti != null) sender.complete()
            sender.run(ch)
            run.sender = null
            // `aktar.bitti` kontrol kanalindan gelir; veri baglantisi kapanisindan biraz gec olabilir.
            var waited = 0
            while (run.bitti == null && !run.cancelled && waited < 30) { Thread.sleep(100); waited++ }
            // Alici `aktar.bitti` ile (kontrol kanali) bitirir; onControl durumu kapatir.
            run.bitti != null || run.cancelled
        }
    }

    private fun progressOut(run: Run, fid: Int, sent: Long) {
        run.sent.merge(fid, sent) { a, b -> maxOf(a, b) }
        pushProgress(run) { run.sent.values.sum() }
    }

    private fun progressIn(run: Run) {
        val rc = run.receiver ?: return
        pushProgress(run) { rc.receivedBytes() }
    }

    /** Arayuz durumu en cok ~5 kez/sn guncellenir. */
    private fun pushProgress(run: Run, bytes: () -> Long) {
        val now = System.nanoTime() / 1_000_000
        if (now - run.lastUi < 200) return
        run.lastUi = now
        val b = bytes()
        val speed = run.meter.update(now, b)
        update(run.aid) { if (it.status == TransferStatus.ACTIVE || it.status == TransferStatus.CONNECTING) it.copy(status = TransferStatus.ACTIVE, doneBytes = b, speedBps = speed) else it }
    }

    // --- Durum ---------------------------------------------------------------------------------------------------

    private fun find(aid: String) = _transfers.value.firstOrNull { it.aid == aid }

    private fun add(t: TransferInfo) = _transfers.update { (listOf(t) + it).take(30) }

    private fun update(aid: String, f: (TransferInfo) -> TransferInfo) =
        _transfers.update { l -> l.map { if (it.aid == aid) f(it) else it } }

    private fun end(aid: String, st: TransferStatus, detail: String?) {
        val t = find(aid)
        if (t == null || (!t.running && t.status != TransferStatus.OFFERED)) return
        update(aid) { it.copy(status = st, detail = detail, speedBps = 0, endedAt = System.currentTimeMillis()) }
        runs[aid]?.let { r -> closeSocket(r) }
        storage.forget(aid)
        // Kayit kalir (tekrar teklif edilemesin), ama bellekte buyumesin.
        if (runs.size > 60) runs.keys.firstOrNull { k -> find(k)?.let { f -> !f.running && f.status != TransferStatus.OFFERED } != false }?.let { runs.remove(it) }
    }

    private fun toast(text: String) {
        Handler(Looper.getMainLooper()).post { Toast.makeText(ctx, text, Toast.LENGTH_SHORT).show() }
    }

    // --- Bildirimler ---------------------------------------------------------------------------------------------

    private suspend fun watchNotifications() {
        val nm = NotificationManagerCompat.from(ctx)
        val seen = HashMap<String, TransferStatus>()
        _transfers.collect { list ->
            try {
                for (t in list) {
                    val prev = seen.put(t.aid, t.status)
                    if (prev == t.status) continue
                    if (t.status == TransferStatus.OFFERED) nm.notify(AktarNotifier.offerId(t.aid), AktarNotifier.offer(ctx, t))
                    else if (prev == TransferStatus.OFFERED) nm.cancel(AktarNotifier.offerId(t.aid))
                    if (t.status == TransferStatus.FAILED || (t.status == TransferStatus.DONE && t.dir == TransferDir.IN)) {
                        nm.notify(AktarNotifier.resultId(t.aid), AktarNotifier.result(ctx, t))
                    }
                }
                val running = list.filter { it.running }
                if (running.isEmpty()) nm.cancel(AktarNotifier.ID_PROGRESS)
                else nm.notify(AktarNotifier.ID_PROGRESS, AktarNotifier.progress(ctx, running.first(), running.size))
            } catch (_: SecurityException) { }
            delay(1000)    // ilerleme bildirimi saniyede 1'den sik degil
        }
    }

    companion object {
        const val DATA_PORT = 47823
    }
}
