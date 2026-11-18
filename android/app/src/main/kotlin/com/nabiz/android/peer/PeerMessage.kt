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
            else -> PeerMessage.Unknown(t, id)
        }
    }
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
