package com.nabiz.android.peer

/**
 * Telefon ozellikleri (arama, kisi, bildirim) icin NabizClient'in konustugu arayuz.
 * Gercek uygulama `phone.PhoneFeatures`; client yalniz oturum akisini ve yonlendirmeyi bilir.
 */
interface PhoneHost {
    /** Oturum kurulurken: oturum basina tutulan onbellekler (ikon, duyurulan bildirimler) sifirlanir. */
    fun onSessionStart()
    fun permState(): PeerMessage.PermState
    /** Mevcut arama durumu (bosta olabilir; cagriYonetimi kapaliysa her zaman bosta). */
    fun callState(): PeerMessage.CallState
    /** Bildirimler kapali ya da erisim yoksa null. */
    fun notifList(): List<PhoneNotif>?
    /** mac->tel isteklerini isler; izin yoksa ayni id ile `error` {izin_yok}. Donenler karsiya yollanir. */
    suspend fun handle(m: PeerMessage): List<PeerMessage>
}
