package com.nabiz.android.peer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** docs/protokol.md bolum 8 vektorleri. */
class PeerCryptoTest {
    private val macPriv = ByteArray(32) { (it + 1).toByte() }
    private val phonePriv = ByteArray(32) { (it + 33).toByte() }
    private val macNonce = ByteArray(16) { (0xa0 + it).toByte() }
    private val phoneNonce = ByteArray(16) { (0xb0 + it).toByte() }
    private val macPubHex = "04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354"
    private val phonePubHex = "041f140146bfb1b251f84f4ddbe0d4cdcfd77afd984a9520e35794021f8312bb9eec995a08b1fa7704df3dcc0b50a9665263fb7711f95f9f8a449c5096e47c892b"

    @Test fun hkdfRfc5869Test1() {
        val ikm = ByteArray(22) { 0x0b }
        val salt = ByteArray(13) { it.toByte() }
        val info = ByteArray(10) { (0xf0 + it).toByte() }
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            hkdfSha256(ikm, salt, info, 42).toHexLower(),
        )
    }

    @Test fun ecdhAndKeyDerivationVector() {
        val macPub = hexToBytes(macPubHex)
        val phonePub = hexToBytes(phonePubHex)
        assertTrue(P256.isValidPoint(macPub)); assertTrue(P256.isValidPoint(phonePub))
        val secret = P256.ecdh(P256.privateKeyFromRaw(macPriv), P256.publicFromX963(phonePub))
        assertEquals("4fe243908f378aa1c2a69538822e6ed908c3225d8692575507c649901245150a", secret.toHexLower())
        // iki yonlu ayni
        assertArrayEquals(secret, P256.ecdh(P256.privateKeyFromRaw(phonePriv), P256.publicFromX963(macPub)))
        val keys = PeerKdf.derive(secret, macPub, phonePub, macNonce, phoneNonce)
        assertEquals("3e7994371738fd367f8393c81893a0371df27a71ed52fdd4142ec49917eccef0", keys.macToPhone.toHexLower())
        assertEquals("cbe20cf9b684bdb2a428ae219e708ce69a45856684940b59a7a0165e3df6aaf8", keys.phoneToMac.toHexLower())
        assertEquals("538801", keys.sas)
    }

    @Test fun x963SerializationMatchesVector() {
        // Ham skalerden acik anahtar: ECDH ile degil, P256.x963(public) ile; acik anahtar vektoru gecerli noktadir ve gidis-donus korunur.
        val pub = hexToBytes(macPubHex)
        assertArrayEquals(pub, P256.x963(P256.publicFromX963(pub)))
        assertFalse(P256.isValidPoint(pub.copyOf().also { it[64] = (it[64] + 1).toByte() }))
    }

    @Test fun aesGcmVector() {
        val key = ByteArray(32) { it.toByte() }
        val plain = """{"id":1,"t":"ping"}""".toByteArray()
        assertEquals(19, plain.size)
        val packet = PeerAead.seal(key, 1, plain)
        assertEquals(
            "00000000000000016ef4d69866ce01322c5a7303ced6539972bd6149d15d86aae12692f305fb8fdc1a15c0",
            packet.toHexLower(),
        )
        assertArrayEquals(plain, PeerAead.open(key, packet).second)
    }

    @Test fun replayAndTamperRejected() {
        val key = ByteArray(32) { it.toByte() }
        val sealer = PeerSealer(key)
        val opener = PeerOpener(key)
        val p1 = sealer.seal("a".toByteArray())
        val p2 = sealer.seal("b".toByteArray())
        assertArrayEquals("a".toByteArray(), opener.open(p1))
        assertArrayEquals("b".toByteArray(), opener.open(p2))
        try { opener.open(p1); fail("tekrar kabul edildi") } catch (_: PeerCryptoException) { }
        try { opener.open(p2); fail("ayni sayac kabul edildi") } catch (_: PeerCryptoException) { }
        val p3 = sealer.seal("c".toByteArray())
        val bad = p3.copyOf().also { it[it.size - 1] = (it[it.size - 1] + 1).toByte() }
        try { opener.open(bad); fail("bozuk etiket kabul edildi") } catch (_: PeerCryptoException) { }
        // dogrulanamayan paket sayaci ilerletmemeli
        assertArrayEquals("c".toByteArray(), opener.open(p3))
        try { opener.open(ByteArray(23)); fail("kisa paket") } catch (_: PeerCryptoException) { }
    }
}
