package com.nabiz.android.peer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.security.KeyStore
import java.security.PrivateKey
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class PinnedMac(val id: String, val name: String, val pub: ByteArray)

class PeerIdentity(val privateKey: PrivateKey, val publicBytes: ByteArray)

/** Kimlik anahtari Android Keystore'daki AES anahtariyla sarilip SharedPreferences'ta saklanir. */
class PeerStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("nabiz_peer", Context.MODE_PRIVATE)
    private val b64e = Base64.getEncoder()
    private val b64d = Base64.getDecoder()

    private val _pinned = MutableStateFlow(readPinned())
    val pinned: StateFlow<PinnedMac?> = _pinned.asStateFlow()

    /** Son basarili Mac baglantisi (epoch ms); 0 = hic. */
    var lastConnected: Long
        get() = prefs.getLong("last_connected", 0L)
        set(v) { prefs.edit().putLong("last_connected", v).apply() }

    /** Uzak adres ("host" ya da "host:port"); bos = yok. Yalniz pinli Mac icin denenir. */
    var remoteAddress: String?
        get() = prefs.getString("remote_address", null)?.takeIf { it.isNotBlank() }
        set(v) { prefs.edit().apply { if (v.isNullOrBlank()) remove("remote_address") else putString("remote_address", v.trim()) }.apply() }

    /** Son basarili oturumun Mac adresi (pinle birlikte; bolum 11). */
    class LastMac(val id: String, val host: String, val port: Int)

    var lastMac: LastMac?
        get() {
            val id = prefs.getString("last_id", null) ?: return null
            val host = prefs.getString("last_host", null) ?: return null
            val port = prefs.getInt("last_port", 0).takeIf { it in 1..65535 } ?: return null
            return LastMac(id, host, port)
        }
        set(v) {
            prefs.edit().apply {
                if (v == null) remove("last_id").remove("last_host").remove("last_port")
                else putString("last_id", v.id).putString("last_host", v.host).putInt("last_port", v.port)
            }.apply()
        }

    val deviceId: String
        @Synchronized get() = prefs.getString("device_id", null)
            ?: UUID.randomUUID().toString().also { prefs.edit().putString("device_id", it).apply() }

    private fun readPinned(): PinnedMac? {
        val id = prefs.getString("pin_id", null) ?: return null
        val pub = prefs.getString("pin_pub", null) ?: return null
        return PinnedMac(id, prefs.getString("pin_name", "") ?: "", b64d.decode(pub))
    }

    fun pin(mac: PinnedMac) {
        prefs.edit().putString("pin_id", mac.id).putString("pin_name", mac.name).putString("pin_pub", b64e.encodeToString(mac.pub)).apply()
        _pinned.value = mac
    }

    fun unpin() {
        prefs.edit().remove("pin_id").remove("pin_name").remove("pin_pub").remove("last_id").remove("last_host").remove("last_port").apply()
        _pinned.value = null
    }

    @Synchronized
    fun identity(): PeerIdentity {
        val blob = prefs.getString("id_blob", null)
        if (blob != null) {
            val plain = decrypt(b64d.decode(blob))
            return PeerIdentity(P256.privateKeyFromRaw(plain.copyOfRange(0, 32)), plain.copyOfRange(32, 97))
        }
        val (priv, pub) = P256.generate()
        prefs.edit().putString("id_blob", b64e.encodeToString(encrypt(priv + pub))).apply()
        return PeerIdentity(P256.privateKeyFromRaw(priv), pub)
    }

    private fun wrapKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, wrapKey())
        return c.iv + c.doFinal(plain)
    }

    private fun decrypt(blob: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, blob, 0, 12))
        return c.doFinal(blob, 12, blob.size - 12)
    }

    private companion object {
        const val ALIAS = "nabiz_peer_wrap"
    }
}
