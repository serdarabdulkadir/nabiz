package com.nabiz.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** docs/fixtures/messages.json ve vectors.json: Mac ile ortak ornekler (docs/protokol.md bolum 7-8). */
class FixtureTest {
    private fun fixture(name: String): Map<*, *> {
        var dir: File? = File(System.getProperty("user.dir") ?: ".").absoluteFile
        while (dir != null) {
            val f = File(dir, "docs/fixtures/$name")
            if (f.isFile) return PeerJson.parse(f.readText()) as Map<*, *>
            dir = dir.parentFile
        }
        throw AssertionError("docs/fixtures/$name bulunamadi")
    }

    /** Sayilar Double'a, haritalar sirasiz karsilastirilacak sekle indirgenir. */
    private fun norm(v: Any?): Any? = when (v) {
        is Number -> v.toDouble()
        is Map<*, *> -> v.entries.associate { (it.key as String) to norm(it.value) }
        is List<*> -> v.map { norm(it) }
        else -> v
    }

    @Test fun everyMessageRoundTrips() {
        val items = fixture("messages.json")["ornekler"] as List<*>
        assertTrue(items.isNotEmpty())
        for (item in items) {
            val ad = (item as Map<*, *>)["ad"]
            val json = item["json"] as Map<*, *>
            val msg = PeerCodec.decode(PeerJson.write(json))
            val back = PeerJson.parse(PeerCodec.encode(msg))
            assertEquals("ornek: $ad", norm(json), norm(back))
        }
    }

    @Test fun pingPongKeepId() {
        val items = (fixture("messages.json")["ornekler"] as List<*>).associate { (it as Map<*, *>)["ad"] to it["json"] as Map<*, *> }
        assertEquals(PeerMessage.Ping(7), PeerCodec.decode(PeerJson.write(items["ping"]!!)))
        assertEquals(PeerMessage.Pong(7), PeerCodec.decode(PeerJson.write(items["pong"]!!)))
    }

    private val v by lazy { fixture("vectors.json") }
    private fun kdf(k: String) = (v["kdf"] as Map<*, *>)[k] as String

    @Test fun handshakeFixtureDecodesAndRebuilds() {
        val hs = (fixture("messages.json")["hs"] as Map<*, *>)["json"] as Map<*, *>
        val phonePriv = P256.privateKeyFromRaw(hexToBytes(kdf("phonePriv")))
        val phone = PeerSession(
            PeerRole.TELEFON, phonePriv, hexToBytes(kdf("phonePub")), "Tel", null, hexToBytes(kdf("phoneNonce")),
            PeerMessage.Hello("Tel", "0.3.0", 1, "id", "android"),
        )
        val ev = phone.receive(PeerFraming.encode(PeerJson.write(hs).toByteArray()))
        assertEquals(kdf("sas"), ev.filterIsInstance<PeerEvent.SasRequired>().single().code)
        assertEquals("MacBook Air", phone.peerName)

        val macPriv = P256.privateKeyFromRaw(hexToBytes(kdf("macPriv")))
        val mac = PeerSession(
            PeerRole.MAC, macPriv, hexToBytes(kdf("macPub")), "MacBook Air", null, hexToBytes(kdf("macNonce")),
            PeerMessage.Hello("MacBook Air", "0.3.0", 1, "id", "mac"),
        )
        val frame = mac.start().filterIsInstance<PeerEvent.Send>().single().bytes
        val rebuilt = PeerJson.parse(String(frame, 4, frame.size - 4, Charsets.UTF_8))
        assertEquals(norm(hs), norm(rebuilt))
    }

    @Test fun hkdfVector() {
        val h = v["hkdf"] as Map<*, *>
        val okm = hkdfSha256(hexToBytes(h["ikm"] as String), hexToBytes(h["salt"] as String), hexToBytes(h["info"] as String), (h["length"] as Number).toInt())
        assertEquals(h["okm"], okm.toHexLower())
    }

    @Test fun kdfVector() {
        val macPub = hexToBytes(kdf("macPub")); val phonePub = hexToBytes(kdf("phonePub"))
        val secret = P256.ecdh(P256.privateKeyFromRaw(hexToBytes(kdf("macPriv"))), P256.publicFromX963(phonePub))
        assertEquals(kdf("secret"), secret.toHexLower())
        val keys = PeerKdf.derive(secret, macPub, phonePub, hexToBytes(kdf("macNonce")), hexToBytes(kdf("phoneNonce")))
        assertEquals(kdf("macToPhone"), keys.macToPhone.toHexLower())
        assertEquals(kdf("phoneToMac"), keys.phoneToMac.toHexLower())
        assertEquals(kdf("sas"), keys.sas)
    }

    @Test fun gcmVector() {
        val g = v["gcm"] as Map<*, *>
        val key = hexToBytes(g["key"] as String)
        val plain = (g["plaintext"] as String).toByteArray(Charsets.UTF_8)
        val packet = PeerAead.seal(key, (g["counter"] as Number).toLong(), plain)
        assertEquals(g["packet"], packet.toHexLower())
        assertArrayEquals(plain, PeerAead.open(key, hexToBytes(g["packet"] as String)).second)
    }

    @Test fun frameVector() {
        val f = v["frame"] as Map<*, *>
        assertEquals(f["framed"], PeerFraming.encode(hexToBytes(f["payload"] as String)).toHexLower())
    }
}
