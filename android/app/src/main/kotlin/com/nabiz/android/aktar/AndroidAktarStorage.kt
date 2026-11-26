package com.nabiz.android.aktar

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import com.nabiz.android.peer.AktarFile
import com.nabiz.android.peer.AktarNames
import com.nabiz.android.peer.AktarPartial
import com.nabiz.android.peer.AktarStorage
import com.nabiz.android.peer.FileAktarPartial
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * Alinan dosyalarin yazildigi yer (docs/protokol.md bolum 13).
 * Android 10+: fotograf -> Pictures/Nabız, video -> Movies/Nabız, digerleri -> Download/Nabız (MediaStore, IS_PENDING = yarim dosya).
 * Android 9 ve alti: uygulamanin harici Indirilenler klasoru + `.nabizpart` (depolama izni istememek icin).
 */
class AndroidAktarStorage(private val ctx: Context) : AktarStorage {
    private val partials = ConcurrentHashMap<String, AktarPartial>()

    override fun freeBytes(): Long = try {
        val dir = if (Build.VERSION.SDK_INT >= 29) Environment.getExternalStorageDirectory() else (ctx.getExternalFilesDir(null) ?: ctx.filesDir)
        StatFs(dir.path).availableBytes
    } catch (_: Exception) { 0L }

    override fun partial(aid: String, f: AktarFile): AktarPartial = partials.getOrPut("$aid/${f.fid}") {
        if (Build.VERSION.SDK_INT >= 29) MediaPartial(ctx, f)
        else FileAktarPartial(File(ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: ctx.filesDir, "Nabız"), AktarNames.sanitize(f.ad), "${aid.take(8)}-${f.fid}")
    }

    /** Aktarim bitti / vazgecildi: yarim dosya kayitlari birakilir. */
    fun forget(aid: String) {
        partials.keys.filter { it.startsWith("$aid/") }.forEach { partials.remove(it) }
    }
}

@RequiresApi(29)
private class MediaPartial(private val ctx: Context, private val f: AktarFile) : AktarPartial {
    private val resolver get() = ctx.contentResolver
    private var uri: Uri? = null
    private val name = AktarNames.sanitize(f.ad)
    private val isImage = f.tur.startsWith("image/")
    private val isVideo = f.tur.startsWith("video/")

    override val length: Long
        get() {
            val u = uri ?: return 0L
            return try { resolver.openFileDescriptor(u, "r")?.use { it.statSize } ?: 0L } catch (_: Exception) { 0L }
        }

    private fun collection(): Uri = when {
        isImage -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        isVideo -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        else -> MediaStore.Downloads.EXTERNAL_CONTENT_URI
    }

    private fun relativePath(): String = when {
        isImage -> "Pictures/Nabız"
        isVideo -> "Movies/Nabız"
        else -> "Download/Nabız"
    }

    private fun exists(col: Uri, rel: String, n: String): Boolean = try {
        resolver.query(
            col, arrayOf(MediaStore.MediaColumns._ID),
            "${MediaStore.MediaColumns.DISPLAY_NAME}=? AND ${MediaStore.MediaColumns.RELATIVE_PATH} IN (?, ?)",
            arrayOf(n, rel, "$rel/"), null,
        )?.use { it.count > 0 } ?: false
    } catch (_: Exception) { false }

    private fun ensureUri(): Uri {
        uri?.let { return it }
        val col = collection()
        val rel = relativePath()
        val finalName = AktarNames.unique(name) { exists(col, rel, it) }
        val v = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, finalName)
            put(MediaStore.MediaColumns.MIME_TYPE, f.tur)
            put(MediaStore.MediaColumns.RELATIVE_PATH, rel)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
            if ((isImage || isVideo) && f.degisme != null) put(MediaStore.MediaColumns.DATE_TAKEN, f.degisme * 1000)
        }
        val u = resolver.insert(col, v) ?: throw IOException("dosya kaydı oluşturulamadı")
        uri = u
        return u
    }

    override fun openRead(): InputStream {
        val u = uri ?: return ByteArrayInputStream(ByteArray(0))
        return resolver.openInputStream(u) ?: ByteArrayInputStream(ByteArray(0))
    }

    override fun openAppend(): OutputStream =
        resolver.openOutputStream(ensureUri(), "wa") ?: throw IOException("dosya açılamadı")

    override fun reset() {
        val u = uri ?: return
        try { resolver.openOutputStream(u, "wt")?.close() } catch (_: Exception) { }
    }

    override fun commit(): String {
        val u = ensureUri()
        val v = ContentValues().apply {
            put(MediaStore.MediaColumns.IS_PENDING, 0)
            // Fotograf: cekim tarihi EXIF'ten (yoksa teklifteki degisme zamani insert'te yazildi).
            if (isImage) exifTakenMs(u)?.let { put(MediaStore.MediaColumns.DATE_TAKEN, it) }
        }
        resolver.update(u, v, null, null)
        return u.toString()
    }

    override fun discard() {
        val u = uri ?: return
        try { resolver.delete(u, null, null) } catch (_: Exception) { }
        uri = null
    }

    private fun exifTakenMs(u: Uri): Long? = try {
        resolver.openInputStream(u)?.use { ins ->
            val s = android.media.ExifInterface(ins).getAttribute(android.media.ExifInterface.TAG_DATETIME_ORIGINAL)
            s?.let { SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).parse(it)?.time }
        }
    } catch (_: Exception) { null }
}
