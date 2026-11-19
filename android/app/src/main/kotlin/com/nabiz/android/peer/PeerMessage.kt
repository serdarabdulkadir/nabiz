package com.nabiz.android.peer

// docs/protokol.md bolum 7. Alan adlari Mac tarafindaki NabizCore/Snapshot.swift ile ayni.

data class CpuStats(val total: Int, val cores: List<Int> = emptyList(), val perfCores: Int? = null, val effCores: Int? = null)
data class MemStats(val used: Long, val total: Long, val pressure: String? = null)
data class DiskStats(val used: Long, val total: Long)
data class BatteryStats(
    val level: Int, val charging: Boolean, val health: Int? = null, val cycles: Int? = null,
    val minutes: Int? = null, val temp: Double? = null,
)
data class NetStats(val up: Long, val down: Long)

/** Olcum ani. `ts` zorunlu, digerleri okunamazsa null (JSON'a yazilmaz). Android cpu yazmaz, gpu Mac'e ozel. */
data class Snapshot(
    val ts: Long,
    val cpu: CpuStats? = null,
    val mem: MemStats? = null,
    val disk: DiskStats? = null,
    val battery: BatteryStats? = null,
    val net: NetStats? = null,
    val gpu: Int? = null,
    val uptime: Long? = null,
    val thermal: String? = null,
)

// docs/protokol.md bolum 10: telefon (arama, kisi, bildirim) mesaj yukleri.
data class ContactNumber(val no: String, val tur: String)
data class ContactRecord(
    val kid: String, val ad: String, val numaralar: List<ContactNumber>, val favori: Boolean,
    val gruplar: List<String> = emptyList(), val foto: String? = null,
)
data class CallLogEntry(val numara: String, val kisiAdi: String?, val yon: String, val zaman: Long, val sureSn: Int)

/** Mac'e giden bildirim (bolum 10 "Bildirim" nesnesi). `ikon` base64 PNG (en cok 64 px, 6 KB). */
data class PhoneNotif(
    val anahtar: String, val paket: String, val uygulama: String, val baslik: String?, val metin: String?,
    val zaman: Long, val yanitlanabilir: Boolean, val kapatilabilir: Boolean, val ikon: String? = null,
)

// docs/protokol.md bolum 12: AI limitleri (Mac'ten gelir, telefon yalniz gosterir).
data class AiLimit(
    val id: String, val ad: String, val yuzde: Int, val sifirlanma: Long? = null, val genel: Boolean = false, val tukenme: Long? = null,
)
data class AiProvider(
    val id: String, val ad: String, val plan: String? = null, val notu: String? = null, val sorun: String? = null,
    val guncel: Long? = null, val limitler: List<AiLimit> = emptyList(),
    /** Hesap basina benzersiz (yerel hesapta saglayici adi, ek hesapta UUID); `hesap`: kullanicinin verdigi ad. */
    val hesapId: String = id, val hesap: String? = null,
)

sealed class PeerMessage {
    abstract val id: Long?

    data class Hello(
        val ad: String, val surum: String, val protokol: Int, val cihazId: String, val platform: String,
        val model: String? = null, override val id: Long? = null,
    ) : PeerMessage()
    data class Ping(override val id: Long? = null) : PeerMessage()
    data class Pong(override val id: Long? = null) : PeerMessage()
    data class Stats(val snap: Snapshot, override val id: Long? = null) : PeerMessage()
    data class Sub(val aralikSn: Int, override val id: Long? = null) : PeerMessage()
    data class Cmd(val eylem: String, override val id: Long? = null) : PeerMessage()
    data class MacState(
        val kilitli: Boolean, val ekranKapali: Boolean, val uykuyaGidiyor: Boolean, override val id: Long? = null,
    ) : PeerMessage()
    data class CmdResult(val eylem: String, val sonuc: String, override val id: Long? = null) : PeerMessage()
    data class Err(val kod: String, val mesaj: String = "", override val id: Long? = null) : PeerMessage()
    data class Unknown(val type: String, override val id: Long? = null) : PeerMessage()

    // --- Bolum 10 ---
    data class PermState(
        val bildirimler: Boolean, val cagriYonetimi: Boolean, val kisiler: Boolean, val aramaGecmisi: Boolean,
        override val id: Long? = null,
    ) : PeerMessage()
    data class CallState(
        val durum: String, val yon: String? = null, val numara: String? = null, val kisiAdi: String? = null,
        val sureSn: Int? = null, override val id: Long? = null,
    ) : PeerMessage()
    data class CallAnswer(override val id: Long? = null) : PeerMessage()
    data class CallReject(override val id: Long? = null) : PeerMessage()
    data class CallHangup(override val id: Long? = null) : PeerMessage()
    data class CallDial(val numara: String, override val id: Long? = null) : PeerMessage()
    data class ContactsSync(val ofset: Int, val adet: Int? = null, override val id: Long? = null) : PeerMessage()
    data class ContactsPage(
        val ofset: Int, val toplam: Int, val son: Boolean, val kisiler: List<ContactRecord>, override val id: Long? = null,
    ) : PeerMessage()
    data class ContactsChanged(override val id: Long? = null) : PeerMessage()
    data class CallLogSync(val ofset: Int, val adet: Int? = null, override val id: Long? = null) : PeerMessage()
    data class CallLogPage(
        val ofset: Int, val toplam: Int, val son: Boolean, val kayitlar: List<CallLogEntry>, override val id: Long? = null,
    ) : PeerMessage()
    data class CallLogChanged(override val id: Long? = null) : PeerMessage()
    data class NotifList(val bildirimler: List<PhoneNotif>, override val id: Long? = null) : PeerMessage()
    data class NotifPosted(val bildirim: PhoneNotif, override val id: Long? = null) : PeerMessage()
    data class NotifRemoved(val anahtar: String, override val id: Long? = null) : PeerMessage()
    data class NotifDismiss(val anahtar: String, override val id: Long? = null) : PeerMessage()
    data class NotifClear(override val id: Long? = null) : PeerMessage()
    data class NotifReply(val anahtar: String, val metin: String, override val id: Long? = null) : PeerMessage()
    data class NotifResult(val anahtar: String, val sonuc: String, override val id: Long? = null) : PeerMessage()
    data class AiState(val saglayicilar: List<AiProvider>, override val id: Long? = null) : PeerMessage()
}

object PeerCodec {
    fun encode(m: PeerMessage): String = PeerJson.write(toMap(m))

    fun toMap(m: PeerMessage): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        m.id?.let { out["id"] = it }
        fun put(k: String, v: Any?) { if (v != null) out[k] = v }
        when (m) {
            is PeerMessage.Hello -> {
                out["t"] = "hello"
                put("ad", m.ad); put("surum", m.surum); put("protokol", m.protokol)
                put("cihazId", m.cihazId); put("platform", m.platform); put("model", m.model)
            }
            is PeerMessage.Ping -> out["t"] = "ping"
            is PeerMessage.Pong -> out["t"] = "pong"
            is PeerMessage.Stats -> { out["t"] = "stats"; out["snap"] = SnapshotCodec.toMap(m.snap) }
            is PeerMessage.Sub -> { out["t"] = "sub"; out["aralikSn"] = m.aralikSn }
            is PeerMessage.Cmd -> { out["t"] = "cmd"; out["eylem"] = m.eylem }
            is PeerMessage.MacState -> {
                out["t"] = "mac.state"
                out["kilitli"] = m.kilitli; out["ekranKapali"] = m.ekranKapali; out["uykuyaGidiyor"] = m.uykuyaGidiyor
            }
            is PeerMessage.CmdResult -> { out["t"] = "cmd.result"; out["eylem"] = m.eylem; out["sonuc"] = m.sonuc }
            is PeerMessage.Err -> { out["t"] = "error"; out["kod"] = m.kod; put("mesaj", m.mesaj.ifEmpty { null }) }
            is PeerMessage.Unknown -> out["t"] = m.type
            is PeerMessage.PermState -> {
                out["t"] = "perm.state"
                out["bildirimler"] = m.bildirimler; out["cagriYonetimi"] = m.cagriYonetimi
                out["kisiler"] = m.kisiler; out["aramaGecmisi"] = m.aramaGecmisi
            }
            is PeerMessage.CallState -> {
                out["t"] = "call.state"; out["durum"] = m.durum
                put("yon", m.yon); put("numara", m.numara); put("kisiAdi", m.kisiAdi); put("sureSn", m.sureSn)
            }
            is PeerMessage.CallAnswer -> out["t"] = "call.answer"
            is PeerMessage.CallReject -> out["t"] = "call.reject"
            is PeerMessage.CallHangup -> out["t"] = "call.hangup"
            is PeerMessage.CallDial -> { out["t"] = "call.dial"; out["numara"] = m.numara }
            is PeerMessage.ContactsSync -> { out["t"] = "contacts.sync"; out["ofset"] = m.ofset; put("adet", m.adet) }
            is PeerMessage.ContactsPage -> {
                out["t"] = "contacts.page"; out["ofset"] = m.ofset; out["toplam"] = m.toplam; out["son"] = m.son
                out["kisiler"] = m.kisiler.map { PhoneCodec.contactMap(it) }
            }
            is PeerMessage.ContactsChanged -> out["t"] = "contacts.changed"
            is PeerMessage.CallLogSync -> { out["t"] = "calllog.sync"; out["ofset"] = m.ofset; put("adet", m.adet) }
            is PeerMessage.CallLogPage -> {
                out["t"] = "calllog.page"; out["ofset"] = m.ofset; out["toplam"] = m.toplam; out["son"] = m.son
                out["kayitlar"] = m.kayitlar.map { PhoneCodec.logMap(it) }
            }
            is PeerMessage.CallLogChanged -> out["t"] = "calllog.changed"
            is PeerMessage.NotifList -> { out["t"] = "notif.list"; out["bildirimler"] = m.bildirimler.map { PhoneCodec.notifMap(it) } }
            is PeerMessage.NotifPosted -> { out["t"] = "notif.posted"; out["bildirim"] = PhoneCodec.notifMap(m.bildirim) }
            is PeerMessage.NotifRemoved -> { out["t"] = "notif.removed"; out["anahtar"] = m.anahtar }
            is PeerMessage.NotifDismiss -> { out["t"] = "notif.dismiss"; out["anahtar"] = m.anahtar }
            is PeerMessage.NotifClear -> out["t"] = "notif.clear"
            is PeerMessage.NotifReply -> { out["t"] = "notif.reply"; out["anahtar"] = m.anahtar; out["metin"] = m.metin }
            is PeerMessage.NotifResult -> { out["t"] = "notif.result"; out["anahtar"] = m.anahtar; out["sonuc"] = m.sonuc }
            is PeerMessage.AiState -> { out["t"] = "ai.state"; out["saglayicilar"] = m.saglayicilar.map { PhoneCodec.aiMap(it) } }
        }
        return out
    }

    /** Bozuk JSON ya da eksik zorunlu alan: PeerProtocolException. Bilinmeyen `t`: Unknown. */
    fun decode(text: String): PeerMessage {
        val root = PeerJson.parse(text) as? Map<*, *> ?: throw PeerProtocolException("mesaj nesne degil")
        val o = Fields(root)
        val t = o.str("t")
        val id = o.longOpt("id")
        return when (t) {
            "hello" -> PeerMessage.Hello(o.str("ad"), o.strOrNumber("surum"), o.int("protokol"), o.str("cihazId"), o.str("platform"), o.strOpt("model"), id)
            "ping" -> PeerMessage.Ping(id)
            "pong" -> PeerMessage.Pong(id)
            "stats" -> PeerMessage.Stats(SnapshotCodec.fromMap(o.map("snap")), id)
            "sub" -> PeerMessage.Sub(o.int("aralikSn"), id)
            "cmd" -> PeerMessage.Cmd(o.str("eylem"), id)
            "mac.state" -> PeerMessage.MacState(o.boolOpt("kilitli"), o.boolOpt("ekranKapali"), o.boolOpt("uykuyaGidiyor"), id)
            "cmd.result" -> PeerMessage.CmdResult(o.str("eylem"), o.str("sonuc"), id)
            "error" -> PeerMessage.Err(o.str("kod"), o.strOpt("mesaj") ?: "", id)
            "perm.state" -> PeerMessage.PermState(o.boolOpt("bildirimler"), o.boolOpt("cagriYonetimi"), o.boolOpt("kisiler"), o.boolOpt("aramaGecmisi"), id)
            "call.state" -> PeerMessage.CallState(o.str("durum"), o.strOpt("yon"), o.strOpt("numara"), o.strOpt("kisiAdi"), o.intOpt("sureSn"), id)
            "call.answer" -> PeerMessage.CallAnswer(id)
            "call.reject" -> PeerMessage.CallReject(id)
            "call.hangup" -> PeerMessage.CallHangup(id)
            "call.dial" -> PeerMessage.CallDial(o.str("numara"), id)
            "contacts.sync" -> PeerMessage.ContactsSync(o.int("ofset"), o.intOpt("adet"), id)
            "contacts.page" -> PeerMessage.ContactsPage(
                o.int("ofset"), o.int("toplam"), o.bool("son"),
                o.listOpt("kisiler").orEmpty().map { PhoneCodec.contact(Fields(it as? Map<*, *> ?: throw PeerProtocolException("kisi nesne degil"))) }, id,
            )
            "contacts.changed" -> PeerMessage.ContactsChanged(id)
            "calllog.sync" -> PeerMessage.CallLogSync(o.int("ofset"), o.intOpt("adet"), id)
            "calllog.page" -> PeerMessage.CallLogPage(
                o.int("ofset"), o.int("toplam"), o.bool("son"),
                o.listOpt("kayitlar").orEmpty().map { PhoneCodec.log(Fields(it as? Map<*, *> ?: throw PeerProtocolException("kayit nesne degil"))) }, id,
            )
            "calllog.changed" -> PeerMessage.CallLogChanged(id)
            "notif.list" -> PeerMessage.NotifList(
                o.listOpt("bildirimler").orEmpty().map { PhoneCodec.notif(Fields(it as? Map<*, *> ?: throw PeerProtocolException("bildirim nesne degil"))) }, id,
            )
            "notif.posted" -> PeerMessage.NotifPosted(PhoneCodec.notif(Fields(o.map("bildirim"))), id)
            "notif.removed" -> PeerMessage.NotifRemoved(o.str("anahtar"), id)
            "notif.dismiss" -> PeerMessage.NotifDismiss(o.str("anahtar"), id)
            "notif.clear" -> PeerMessage.NotifClear(id)
            "notif.reply" -> PeerMessage.NotifReply(o.str("anahtar"), o.str("metin"), id)
            "notif.result" -> PeerMessage.NotifResult(o.str("anahtar"), o.str("sonuc"), id)
            "ai.state" -> PeerMessage.AiState(
                o.listOpt("saglayicilar").orEmpty().map { PhoneCodec.ai(Fields(it as? Map<*, *> ?: throw PeerProtocolException("saglayici nesne degil"))) }, id,
            )
            else -> PeerMessage.Unknown(t, id)
        }
    }
}

/** Bolum 10 ic nesneleri (kisi, arama kaydi, bildirim) <-> JSON haritasi. */
internal object PhoneCodec {
    fun contactMap(c: ContactRecord): Map<String, Any?> {
        val m = hashMapOf<String, Any?>(
            "kid" to c.kid, "ad" to c.ad, "favori" to c.favori, "gruplar" to c.gruplar,
            "numaralar" to c.numaralar.map { mapOf("no" to it.no, "tur" to it.tur) },
        )
        c.foto?.let { m["foto"] = it }
        return m
    }

    fun contact(f: Fields) = ContactRecord(
        f.str("kid"), f.str("ad"),
        f.listOpt("numaralar").orEmpty().map { n -> Fields(n as? Map<*, *> ?: throw PeerProtocolException("numara nesne degil")).let { ContactNumber(it.str("no"), it.str("tur")) } },
        f.boolOpt("favori"), f.listOpt("gruplar").orEmpty().mapNotNull { it as? String }, f.strOpt("foto"),
    )

    fun logMap(e: CallLogEntry): Map<String, Any?> {
        val m = hashMapOf<String, Any?>("numara" to e.numara, "yon" to e.yon, "zaman" to e.zaman, "sureSn" to e.sureSn)
        e.kisiAdi?.let { m["kisiAdi"] = it }
        return m
    }

    fun log(f: Fields) = CallLogEntry(f.str("numara"), f.strOpt("kisiAdi"), f.str("yon"), f.long("zaman"), f.int("sureSn"))

    fun notifMap(n: PhoneNotif): Map<String, Any?> {
        val m = hashMapOf<String, Any?>(
            "anahtar" to n.anahtar, "paket" to n.paket, "uygulama" to n.uygulama, "zaman" to n.zaman,
            "yanitlanabilir" to n.yanitlanabilir, "kapatilabilir" to n.kapatilabilir,
        )
        n.baslik?.let { m["baslik"] = it }
        n.metin?.let { m["metin"] = it }
        n.ikon?.let { m["ikon"] = it }
        return m
    }

    fun aiMap(p: AiProvider): Map<String, Any?> {
        val m = hashMapOf<String, Any?>(
            "id" to p.id, "ad" to p.ad, "hesapId" to p.hesapId,
            "limitler" to p.limitler.map { l ->
                val x = hashMapOf<String, Any?>("id" to l.id, "ad" to l.ad, "yuzde" to l.yuzde, "genel" to l.genel)
                l.sifirlanma?.let { x["sifirlanma"] = it }
                l.tukenme?.let { x["tukenme"] = it }
                x
            },
        )
        p.hesap?.let { m["hesap"] = it }
        p.plan?.let { m["plan"] = it }
        p.notu?.let { m["not"] = it }
        p.sorun?.let { m["sorun"] = it }
        p.guncel?.let { m["guncel"] = it }
        return m
    }

    fun ai(f: Fields) = AiProvider(
        f.str("id"), f.str("ad"), f.strOpt("plan"), f.strOpt("not"), f.strOpt("sorun"), f.longOpt("guncel"),
        f.listOpt("limitler").orEmpty().map { l ->
            Fields(l as? Map<*, *> ?: throw PeerProtocolException("limit nesne degil")).let {
                AiLimit(it.str("id"), it.str("ad"), it.int("yuzde"), it.longOpt("sifirlanma"), it.boolOpt("genel"), it.longOpt("tukenme"))
            }
        },
        f.strOpt("hesapId") ?: f.str("id"), f.strOpt("hesap"),
    )

    fun notif(f: Fields) = PhoneNotif(
        f.str("anahtar"), f.str("paket"), f.str("uygulama"), f.strOpt("baslik"), f.strOpt("metin"),
        f.long("zaman"), f.boolOpt("yanitlanabilir"), f.boolOpt("kapatilabilir"), f.strOpt("ikon"),
    )
}

object SnapshotCodec {
    fun toMap(s: Snapshot): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["ts"] = s.ts
        s.cpu?.let { c ->
            val m = HashMap<String, Any?>()
            m["total"] = c.total; m["cores"] = c.cores
            c.perfCores?.let { m["perfCores"] = it }
            c.effCores?.let { m["effCores"] = it }
            out["cpu"] = m
        }
        s.mem?.let { m ->
            val x = hashMapOf<String, Any?>("used" to m.used, "total" to m.total)
            m.pressure?.let { x["pressure"] = it }
            out["mem"] = x
        }
        s.disk?.let { out["disk"] = mapOf("used" to it.used, "total" to it.total) }
        s.battery?.let { b ->
            val x = hashMapOf<String, Any?>("level" to b.level, "charging" to b.charging)
            b.health?.let { x["health"] = it }
            b.cycles?.let { x["cycles"] = it }
            b.minutes?.let { x["minutes"] = it }
            b.temp?.let { x["temp"] = it }
            out["battery"] = x
        }
        s.net?.let { out["net"] = mapOf("up" to it.up, "down" to it.down) }
        s.gpu?.let { out["gpu"] = it }
        s.uptime?.let { out["uptime"] = it }
        s.thermal?.let { out["thermal"] = it }
        return out
    }

    fun fromMap(root: Map<*, *>): Snapshot {
        val o = Fields(root)
        val cpu = o.mapOpt("cpu")?.let {
            val f = Fields(it)
            CpuStats(f.int("total"), f.listOpt("cores")?.mapNotNull { n -> (n as? Number)?.toInt() } ?: emptyList(), f.intOpt("perfCores"), f.intOpt("effCores"))
        }
        val mem = o.mapOpt("mem")?.let { val f = Fields(it); MemStats(f.long("used"), f.long("total"), f.strOpt("pressure")) }
        val disk = o.mapOpt("disk")?.let { val f = Fields(it); DiskStats(f.long("used"), f.long("total")) }
        val bat = o.mapOpt("battery")?.let {
            val f = Fields(it)
            BatteryStats(f.int("level"), f.bool("charging"), f.intOpt("health"), f.intOpt("cycles"), f.intOpt("minutes"), f.doubleOpt("temp"))
        }
        val net = o.mapOpt("net")?.let { val f = Fields(it); NetStats(f.long("up"), f.long("down")) }
        return Snapshot(o.long("ts"), cpu, mem, disk, bat, net, o.intOpt("gpu"), o.longOpt("uptime"), o.strOpt("thermal"))
    }
}

internal class Fields(val m: Map<*, *>) {
    fun str(k: String): String = m[k] as? String ?: throw PeerProtocolException("eksik alan: $k")
    fun strOpt(k: String): String? = m[k] as? String
    fun strOrNumber(k: String): String = when (val v = m[k]) {
        is String -> v
        is Number -> v.toString()
        else -> throw PeerProtocolException("eksik alan: $k")
    }
    fun long(k: String): Long = (m[k] as? Number)?.toLong() ?: throw PeerProtocolException("eksik alan: $k")
    fun longOpt(k: String): Long? = (m[k] as? Number)?.toLong()
    fun int(k: String): Int = long(k).toInt()
    fun intOpt(k: String): Int? = longOpt(k)?.toInt()
    fun doubleOpt(k: String): Double? = (m[k] as? Number)?.toDouble()
    fun bool(k: String): Boolean = m[k] as? Boolean ?: throw PeerProtocolException("eksik alan: $k")
    fun boolOpt(k: String): Boolean = m[k] as? Boolean ?: false
    fun map(k: String): Map<*, *> = m[k] as? Map<*, *> ?: throw PeerProtocolException("eksik alan: $k")
    fun mapOpt(k: String): Map<*, *>? = m[k] as? Map<*, *>
    fun listOpt(k: String): List<*>? = m[k] as? List<*>
}
