package com.nabiz.android.peer

import java.security.MessageDigest

// docs/protokol.md bolum 13: Aktar veri baglantisinin anahtarlari. Android'e bagimli degil.

/** `senderToReceiver`: aktar.teklif'i yollayanin yazdigi yon; `receiverToSender`: tersi. */
class AktarKeys(val senderToReceiver: ByteArray, val receiverToSender: ByteArray)

enum class AktarRole { SENDER, RECEIVER }

object AktarCrypto {
    private val INFO = "nabiz/aktar/v1".toByteArray(Charsets.US_ASCII)

    /** Oturumun okm[0..64) degeri = macToPhone || phoneToMac (bolum 4). */
    fun sessionMaterial(keys: SessionKeys): ByteArray = keys.macToPhone + keys.phoneToMac

    /** HKDF-SHA256(ikm = oturum okm[0..64), salt = SHA-256(UTF-8 aid), info = "nabiz/aktar/v1", L = 64). */
    fun deriveKeys(sessionOkm: ByteArray, aid: String): AktarKeys {
        require(sessionOkm.size == 64) { "oturum anahtar malzemesi 64 bayt olmali" }
        val salt = MessageDigest.getInstance("SHA-256").digest(aid.toByteArray(Charsets.UTF_8))
        val okm = hkdfSha256(sessionOkm, salt, INFO, 64)
        return AktarKeys(okm.copyOfRange(0, 32), okm.copyOfRange(32, 64))
    }

    /** Bu baglantida yazarken ve okurken kullanilacak anahtarlar (yazma, okuma). */
    fun keysFor(role: AktarRole, k: AktarKeys): Pair<ByteArray, ByteArray> =
        if (role == AktarRole.SENDER) k.senderToReceiver to k.receiverToSender else k.receiverToSender to k.senderToReceiver
}
