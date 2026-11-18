package com.nabiz.android.peer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PeerMessageTest {
    private val snap = Snapshot(
        ts = 1_700_000_000,
        cpu = CpuStats(23, listOf(10, 40), 1, 1),
        mem = MemStats(8_000_000_000, 16_000_000_000, "warn"),
        disk = DiskStats(100, 200),
        battery = BatteryStats(80, true, 95, 120, 45, 31.5),
        net = NetStats(1000, 2000),
        gpu = 12, uptime = 3600, thermal = "normal",
    )

    @Test fun snapshotRoundTripFull() {
        val text = PeerCodec.encode(PeerMessage.Stats(snap, 7))
        val back = PeerCodec.decode(text) as PeerMessage.Stats
        assertEquals(snap, back.snap)
        assertEquals(7L, back.id)
    }

    @Test fun androidSnapshotOmitsMissingFields() {
        val s = Snapshot(ts = 5, battery = BatteryStats(50, false, temp = 30.0), uptime = 10)
        val text = PeerCodec.encode(PeerMessage.Stats(s))
        assertEquals(
            """{"snap":{"battery":{"charging":false,"level":50,"temp":30.0},"ts":5,"uptime":10},"t":"stats"}""",
            text,
        )
        assertFalse(text.contains("null")); assertFalse(text.contains("cpu"))
        assertEquals(s, (PeerCodec.decode(text) as PeerMessage.Stats).snap)
    }

    @Test fun macSnapshotWithUnknownExtraFieldDecodes() {
        val json = """{"t":"stats","snap":{"ts":9,"cpu":{"total":12,"cores":[1,2,3],"x":1},"gpu":4,"zzz":true}}"""
        val m = PeerCodec.decode(json) as PeerMessage.Stats
        assertEquals(12, m.snap.cpu!!.total); assertEquals(listOf(1, 2, 3), m.snap.cpu!!.cores); assertEquals(4, m.snap.gpu)
    }

    @Test fun controlMessages() {
        assertEquals("""{"aralikSn":2,"t":"sub"}""", PeerCodec.encode(PeerMessage.Sub(2)))
        assertEquals("""{"eylem":"kilitle","id":3,"t":"cmd"}""", PeerCodec.encode(PeerMessage.Cmd("kilitle", 3)))
        assertEquals(PeerMessage.CmdResult("uyut", "kapali"), PeerCodec.decode("""{"t":"cmd.result","eylem":"uyut","sonuc":"kapali"}"""))
        assertEquals("""{"id":1,"t":"ping"}""", PeerCodec.encode(PeerMessage.Ping(1)))
        val h = PeerMessage.Hello("Redmi", "0.1.0", 1, "abc", "android", "Redmi Note 13 Pro")
        assertEquals(h, PeerCodec.decode(PeerCodec.encode(h)))
        assertEquals("""{"kod":"bilinmeyen_tip","t":"error"}""", PeerCodec.encode(PeerMessage.Err("bilinmeyen_tip")))
    }

    @Test fun macStateRoundTrip() {
        val m = PeerMessage.MacState(kilitli = true, ekranKapali = false, uykuyaGidiyor = true)
        assertEquals("""{"ekranKapali":false,"kilitli":true,"t":"mac.state","uykuyaGidiyor":true}""", PeerCodec.encode(m))
        assertEquals(m, PeerCodec.decode(PeerCodec.encode(m)))
        assertEquals("""{"eylem":"uyandir","t":"cmd"}""", PeerCodec.encode(PeerMessage.Cmd("uyandir")))
    }

    @Test fun remoteAddressParse() {
        assertEquals(RemoteAddress("100.64.0.1", 47821), RemoteAddress.parse(" 100.64.0.1 "))
        assertEquals(RemoteAddress("mac-adi", 5000), RemoteAddress.parse("mac-adi:5000"))
        assertEquals(RemoteAddress("::1", 9), RemoteAddress.parse("[::1]:9"))
        assertNull(RemoteAddress.parse("")); assertNull(RemoteAddress.parse("a:x"))
    }

    @Test fun unknownTypeAndBrokenJson() {
        assertTrue(PeerCodec.decode("""{"t":"call.dial","id":2,"numara":"555"}""") is PeerMessage.Unknown)
        try { PeerCodec.decode("{bozuk"); fail() } catch (_: PeerProtocolException) { }
        try { PeerCodec.decode("""{"t":"stats"}"""); fail() } catch (_: PeerProtocolException) { }
    }
}
