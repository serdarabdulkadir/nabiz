package com.nabiz.android.peer

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.SecureRandom

enum class LinkPhase { IDLE, SEARCHING, CONNECTING, AWAIT_SAS, READY }

/** Kopma nedeni (arayuzde tek satir). */
enum class LinkReason { NONE, NOT_FOUND, LOST, REJECTED, KEY_CHANGED, PROTOCOL, SLEEPING, VERSION }

/** Baglanti yolu: yerel ag (NSD) ya da uzak adres (Tailscale). */
enum class LinkVia { LOCAL, REMOTE }

/** Arayuzun ve bildirimin gordugu bagli Mac durumu. */
data class LinkState(
    val phase: LinkPhase = LinkPhase.IDLE,
    val macName: String? = null,
    val sas: String? = null,
    /** Mac'ten gelen son olcum ve alinma zamani (epoch ms). */
    val macSnap: Snapshot? = null,
    val macSnapAt: Long = 0L,
    val reason: LinkReason = LinkReason.NONE,
    /** Mac'ten gelen son mac.state; kopunca korunur (uykuya gidis bilgisi icin). */
    val macState: PeerMessage.MacState? = null,
    val via: LinkVia = LinkVia.LOCAL,
    /** Mac'ten son mesajin alindigi an (epoch ms): "son gorulme". */
    val lastSeenAt: Long = 0L,
    /** Son 5 ping-pong olcumunun ortancasi (ms); olcum yoksa null. */
    val rttMs: Int? = null,
    /** Surum uyumsuzlugunda karsinin protokol surumu (reason = VERSION). */
    val peerVersion: Int? = null,
)

/** Kopus nedeni: Mac uykuya gidiyordu dedikten sonra kopus (ya da bulunamama) "uykuda" sayilir. */
fun disconnectReason(base: LinkReason, macState: PeerMessage.MacState?): LinkReason =
    if ((base == LinkReason.LOST || base == LinkReason.NOT_FOUND) && macState?.uykuyaGidiyor == true) LinkReason.SLEEPING else base

data class CmdOutcome(val eylem: String, val sonuc: String)

/**
 * Telefon (istemci) tarafi: Mac'i bulur, baglanir, oturumu tutar, kopunca geri cekilmeyle yeniden dener.
 * PeerSession tek iplik kullanimli oldugu icin tum erisim `lock` altindadir; yazma ayri kanaldan sirayla yapilir.
 */
class NabizClient(
    private val store: PeerStore,
    private val discovery: MacDiscovery,
    private val ownName: String,
    private val ownModel: String,
    private val appVersion: String,
    private val statsProvider: () -> Snapshot?,
    private val host: PhoneHost? = null,
) {
    private val _state = MutableStateFlow(LinkState())
    val state: StateFlow<LinkState> = _state.asStateFlow()

    private val _results = MutableSharedFlow<CmdOutcome>(extraBufferCapacity = 8)
    val results: SharedFlow<CmdOutcome> = _results.asSharedFlow()

    /** Mac'in bizden istedigi stats araligi (sn); varsayilan 10. */
    private val _peerInterval = MutableStateFlow(10)
    val peerInterval: StateFlow<Int> = _peerInterval.asStateFlow()

    private val lock = Any()
    private var session: PeerSession? = null
    private var writer: Channel<ByteArray>? = null
    private var socket: Socket? = null
    private var job: Job? = null
    private var desiredSub = 10
    private var nextId = 1L
    private val rtt = RttTracker()
    private var versionPeer: Int? = null
    private var localClose: CloseReason? = null
    @Volatile private var readyReached = false
    @Volatile private var connScope: CoroutineScope? = null

    fun start(scope: CoroutineScope) {
        if (job != null) return
        discovery.start()
        job = scope.launch(Dispatchers.IO) { loop() }
    }

    fun stop() {
        job?.cancel(); job = null
        closeSocket()
        discovery.stop()
        _state.value = LinkState()
    }

    /** Eslesmeyi unut: pin silinir, baglanti kapanir; dongu yeniden aramaya baslar. */
    fun unpair() {
        store.unpin()
        closeSocket()
        _state.update { it.copy(macSnap = null, macSnapAt = 0L, macState = null) }
    }

    fun confirmSas(accepted: Boolean) = withSession { it.confirmSas(accepted) }

    /** Ekran durumuna gore Mac'ten istenen stats araligi (1..60 sn). */
    fun requestSub(seconds: Int) {
        desiredSub = seconds.coerceIn(1, 60)
        withSession { if (it.phase == PeerSession.Phase.READY) it.send(PeerMessage.Sub(desiredSub)) else emptyList() }
    }

    fun sendStats(snap: Snapshot) = withSession { it.send(PeerMessage.Stats(snap)) }

    fun sendCmd(eylem: String) = withSession { it.send(PeerMessage.Cmd(eylem, nextId++)) }

    /** Hazir oturumda herhangi bir mesaj yollar (telefon ozellikleri: bildirim, arama durumu...); oturum yoksa atilir. */
    fun send(m: PeerMessage) = withSession { if (it.phase == PeerSession.Phase.READY) it.send(m) else emptyList() }

    fun sendPing() = withSession { it.send(PeerMessage.Ping(rtt.onSent(System.nanoTime()))) }

    private fun withSession(block: (PeerSession) -> List<PeerEvent>) {
        synchronized(lock) {
            val s = session ?: return
            handle(block(s))?.let { localClose = it }
            if (localClose != null) {
                writer?.close()   // yazici kuyrugu bosalinca soket kapanir
                try { socket?.close() } catch (_: Exception) { }
            }
        }
    }

    private fun closeSocket() {
        synchronized(lock) {
            writer?.close(); writer = null
            try { socket?.close() } catch (_: Exception) { }
            socket = null
            session = null
        }
    }

    private fun pick(list: List<MacService>): MacService? {
        val pin = store.pinned.value
        return if (pin != null) list.firstOrNull { it.id == pin.id } else list.firstOrNull()
    }

    private suspend fun loop() {
        val backoff = ReconnectBackoff()
        val scope = CoroutineScope(currentCoroutineContext())
        while (scope.isActive) {
            _state.update { it.copy(phase = LinkPhase.SEARCHING, sas = null) }
            val wait = backoff.next()
            val target = pick(discovery.found.value) ?: withTimeoutOrNull(wait) {
                discovery.found.first { pick(it) != null }
                pick(discovery.found.value)
            }
            var via = LinkVia.LOCAL
            var conn = target
            if (conn == null) {
                conn = remoteTarget()
                if (conn != null) via = LinkVia.REMOTE
            }
            if (conn == null) {
                android.util.Log.i("NabizLink", "Mac bulunamadi, kesif yeniden")
                _state.update { it.copy(reason = disconnectReason(LinkReason.NOT_FOUND, it.macState)) }
                discovery.restart()
                continue
            }
            val chosen: MacService = conn
            _state.update { it.copy(phase = LinkPhase.CONNECTING, macName = chosen.name, via = via) }
            android.util.Log.i("NabizLink", "baglaniyor ($via)")
            readyReached = false
            var reason = runConnection(chosen, backoff)
            if (via == LinkVia.REMOTE && !readyReached && reason == LinkReason.LOST) reason = LinkReason.NOT_FOUND
            android.util.Log.i("NabizLink", "koptu: $reason")
            _state.update { it.copy(phase = LinkPhase.SEARCHING, sas = null, reason = disconnectReason(reason, it.macState), rttMs = null, peerVersion = if (reason == LinkReason.VERSION) versionPeer else null) }
            // Mac yeniden baslayinca port degisir; NSD eski cozumu "guncelleme" olarak bildirir ve
            // onServiceFound tekrar gelmez. Her kopuşta kesfi bastan baslat ki bayat adres kullanilmasin.
            discovery.restart()
            // Surum uyumsuzlugu hizli yeniden deneme dongusune girmez: en uzun geri cekilme.
            delay(if (reason == LinkReason.VERSION) backoff.longest() else wait)
        }
    }

    /** Pin varsa ve uzak adres yazilmissa uzak hedef (cozumleme IO'da). Pinsiz uzak adres denenmez. */
    private suspend fun remoteTarget(): MacService? {
        val pin = store.pinned.value ?: return null
        val addr = RemoteAddress.parse(store.remoteAddress) ?: return null
        return withContext(Dispatchers.IO) {
            try {
                MacService("remote", pin.id, pin.name, InetAddress.getByName(addr.host), addr.port)
            } catch (_: Exception) { null }
        }
    }

    private suspend fun runConnection(target: MacService, backoff: ReconnectBackoff): LinkReason {
        localClose = null
        versionPeer = null
        rtt.reset()
        val sock = Socket()
        val wr = Channel<ByteArray>(Channel.UNLIMITED)
        val scope = CoroutineScope(currentCoroutineContext())
        connScope = scope
        var writerJob: Job? = null
        var pingJob: Job? = null
        try {
            sock.tcpNoDelay = true
            sock.connect(InetSocketAddress(target.host, target.port), 10_000)
            sock.soTimeout = timeoutFor(PeerSession.Phase.HANDSHAKE)
            val ident = store.identity()
            val nonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
            val hello = PeerMessage.Hello(ownName, appVersion, 1, store.deviceId, "android", ownModel)
            val sess = PeerSession(PeerRole.TELEFON, ident.privateKey, ident.publicBytes, ownName, store.pinned.value?.pub, nonce, hello)
            synchronized(lock) { socket = sock; session = sess; writer = wr; curTarget = target; curBackoff = backoff }
            writerJob = scope.launch(Dispatchers.IO) {
                try {
                    val out = sock.getOutputStream()
                    for (b in wr) { out.write(b); out.flush() }
                } catch (_: Exception) { try { sock.close() } catch (_: Exception) { } }
            }
            // Ping 15 sn'de bir; karsidan 45 sn hicbir sey gelmezse okuma zaman asimina duser.
            pingJob = scope.launch {
                while (true) { delay(15_000); sendPing() }
            }
            var closed: CloseReason? = null
            synchronized(lock) { closed = handle(sess.start()) }
            val input = sock.getInputStream()
            val buf = ByteArray(16 * 1024)
            while (scope.isActive && closed == null) {
                val n = try { input.read(buf) } catch (e: java.net.SocketTimeoutException) { return reasonOf(localClose) }
                if (n < 0) return reasonOf(localClose)
                val chunk = buf.copyOf(n)
                synchronized(lock) {
                    val prev = sess.phase
                    closed = handle(sess.receive(chunk))
                    if (sess.phase != prev) sock.soTimeout = timeoutFor(sess.phase)
                }
            }
            return reasonOf(closed)
        } catch (e: Exception) {
            android.util.Log.w("NabizLink", "baglanti hatasi", e)
            return reasonOf(localClose)
        } finally {
            connScope = null
            pingJob?.cancel()
            writerJob?.cancel()
            closeSocket()
            try { sock.close() } catch (_: Exception) { }
        }
    }

    private fun reasonOf(c: CloseReason?): LinkReason = when (c) {
        CloseReason.SAS_REJECTED -> LinkReason.REJECTED
        CloseReason.KEY_CHANGED -> LinkReason.KEY_CHANGED
        CloseReason.VERSION -> LinkReason.VERSION
        CloseReason.PROTOCOL, CloseReason.ROLE, CloseReason.CRYPTO -> LinkReason.PROTOCOL
        else -> LinkReason.LOST
    }

    private fun timeoutFor(p: PeerSession.Phase) = when (p) {
        PeerSession.Phase.HANDSHAKE -> 10_000
        PeerSession.Phase.AWAIT_SAS -> 60_000
        else -> 45_000
    }

    private var curTarget: MacService? = null
    private var curBackoff: ReconnectBackoff? = null

    /** `lock` altinda cagrilir. */
    private fun handle(events: List<PeerEvent>): CloseReason? {
        var closed: CloseReason? = null
        var ready = false
        for (e in events) when (e) {
            is PeerEvent.Send -> writer?.trySend(e.bytes)
            is PeerEvent.SasRequired -> _state.update { it.copy(phase = LinkPhase.AWAIT_SAS, sas = e.code) }
            is PeerEvent.Paired -> store.pin(PinnedMac(curTarget?.id ?: "", e.peerName, e.peerPub))
            is PeerEvent.Ready -> {
                ready = true
                readyReached = true
                curBackoff?.reset()
                store.lastConnected = System.currentTimeMillis()
                _state.update { it.copy(phase = LinkPhase.READY, sas = null, reason = LinkReason.NONE, macState = null, lastSeenAt = System.currentTimeMillis()) }
            }
            is PeerEvent.Received -> onMessage(e.message)
            is PeerEvent.Closed -> {
                closed = e.reason
                if (e.reason == CloseReason.VERSION) versionPeer = session?.peerVersion
                android.util.Log.i("NabizLink", "oturum kapandi: ${e.reason}")
            }
        }
        if (ready) {
            // Sira: hello (oturum yolladi), sub, hemen bir stats.
            val s = session
            if (s != null) {
                emit(s.send(PeerMessage.Sub(desiredSub)))
                emit(s.send(PeerMessage.Ping(rtt.onSent(System.nanoTime()))))
                statsProvider()?.let { emit(s.send(PeerMessage.Stats(it))) }
                pushPhoneState()
            }
        }
        return closed
    }

    /** Oturum kurulunca: perm.state, call.state (bosta degilse), bildirimler aciksa notif.list. Kilit disinda (IO'da) hazirlanir. */
    private fun pushPhoneState() {
        val h = host ?: return
        val sc = connScope ?: return
        sc.launch(Dispatchers.IO) {
            try {
                h.onSessionStart()
                send(h.permState())
                h.callState().takeIf { it.durum != "bosta" }?.let { send(it) }
                h.notifList()?.let { send(PeerMessage.NotifList(it)) }
            } catch (e: Exception) {
                android.util.Log.w("NabizLink", "telefon durumu yollanamadi", e)
            }
        }
    }

    /** mac->tel telefon istegi: kilit disinda islenir, yanitlar ayni oturumdan gider (izin yoksa host `izin_yok` doner). */
    private fun dispatchToHost(m: PeerMessage) {
        val h = host
        val sc = connScope
        if (h == null || sc == null) { session?.let { emit(it.send(PeerMessage.Err("bilinmeyen_tip", "telefon", m.id))) }; return }
        sc.launch(Dispatchers.IO) {
            val replies = try { h.handle(m) } catch (e: Exception) {
                android.util.Log.w("NabizLink", "telefon istegi hatasi", e)
                listOf(PeerMessage.Err("hata", "İşlem yapılamadı", m.id))
            }
            for (r in replies) send(r)
        }
    }

    private fun emit(events: List<PeerEvent>) {
        for (ev in events) if (ev is PeerEvent.Send) writer?.trySend(ev.bytes)
    }

    private fun onMessage(m: PeerMessage) {
        val s = session ?: return
        _state.update { it.copy(lastSeenAt = System.currentTimeMillis()) }
        when (m) {
            is PeerMessage.MacState -> _state.update { it.copy(macState = m) }
            is PeerMessage.Hello -> {
                _state.update { it.copy(macName = m.ad) }
                if (m.protokol != 1) {
                    // hello.protokol da hs.v gibi karsilastirilir: uyumsuzsa oturum kapatilir.
                    versionPeer = m.protokol
                    localClose = CloseReason.VERSION
                    writer?.close()
                    try { socket?.close() } catch (_: Exception) { }
                }
            }
            is PeerMessage.Ping -> emit(s.send(PeerMessage.Pong(m.id)))
            is PeerMessage.Stats -> _state.update { it.copy(macSnap = m.snap, macSnapAt = System.currentTimeMillis()) }
            is PeerMessage.Sub -> _peerInterval.value = m.aralikSn.coerceIn(1, 60)
            is PeerMessage.CmdResult -> _results.tryEmit(CmdOutcome(m.eylem, m.sonuc))
            is PeerMessage.Cmd -> emit(s.send(PeerMessage.Err("bilinmeyen_tip", "cmd", m.id)))
            is PeerMessage.Unknown -> emit(s.send(PeerMessage.Err("bilinmeyen_tip", m.type, m.id)))
            is PeerMessage.Pong -> rtt.onPong(m.id, System.nanoTime())?.let { ms -> _state.update { it.copy(rttMs = ms) } }
            is PeerMessage.Err -> {}
            is PeerMessage.CallAnswer, is PeerMessage.CallReject, is PeerMessage.CallHangup, is PeerMessage.CallDial,
            is PeerMessage.ContactsSync, is PeerMessage.CallLogSync,
            is PeerMessage.NotifDismiss, is PeerMessage.NotifClear, is PeerMessage.NotifReply -> dispatchToHost(m)
            // Telefondan Mac'e giden tipler: Mac yollamaz, yok sayilir.
            is PeerMessage.PermState, is PeerMessage.CallState, is PeerMessage.ContactsPage, is PeerMessage.ContactsChanged,
            is PeerMessage.CallLogPage, is PeerMessage.CallLogChanged, is PeerMessage.NotifList, is PeerMessage.NotifPosted,
            is PeerMessage.NotifRemoved, is PeerMessage.NotifResult -> {}
        }
    }
}
