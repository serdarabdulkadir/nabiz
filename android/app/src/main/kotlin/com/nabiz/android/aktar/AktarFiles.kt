package com.nabiz.android.aktar

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.nabiz.android.peer.AktarFile

/** Gonderilecek uri'lerin ad / boyut / tur / degisme bilgisi (ContentResolver). Disk/IO yapar: ana iplikte cagirma. */
object AktarFiles {
    private data class Meta(val name: String?, val size: Long?, val modifiedSec: Long?)

    private fun query(r: ContentResolver, u: Uri): Meta {
        var name: String? = null
        var size: Long? = null
        var mod: Long? = null
        try {
            r.query(u, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }?.let { name = c.getString(it) }
                    c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 }?.let { if (!c.isNull(it)) size = c.getLong(it) }
                    // SAF belgeleri: last_modified (ms); MediaStore: date_modified (sn).
                    c.getColumnIndex("last_modified").takeIf { it >= 0 }?.let { if (!c.isNull(it)) mod = c.getLong(it) / 1000 }
                    if (mod == null) c.getColumnIndex("date_modified").takeIf { it >= 0 }?.let { if (!c.isNull(it)) mod = c.getLong(it) }
                }
            }
        } catch (_: Exception) { }
        return Meta(name, size, mod)
    }

    /** Boyutu bulunamayan dosya null (gonderilemez). */
    fun describe(ctx: Context, u: Uri, fid: Int): AktarFile? {
        val r = ctx.contentResolver
        val m = query(r, u)
        var size: Long? = m.size?.takeIf { it >= 0 }
        if (size == null) {
            size = try { r.openAssetFileDescriptor(u, "r")?.use { it.length }?.takeIf { it >= 0 } } catch (_: Exception) { null }
        }
        val finalSize: Long = size ?: return null
        val name = m.name?.takeIf { it.isNotBlank() } ?: u.lastPathSegment ?: "dosya"
        val tur: String = (try { r.getType(u) } catch (_: Exception) { null }) ?: "application/octet-stream"
        return AktarFile(fid, name, finalSize, tur, m.modifiedSec?.takeIf { it > 0 })
    }

    /** Paylas sayfasinda gosterilen toplam boyut (bilinmeyenler atlanir). */
    fun totalSize(ctx: Context, uris: List<Uri>): Long = uris.sumOf { u ->
        val r = ctx.contentResolver
        query(r, u).size?.takeIf { it >= 0 } ?: 0L
    }
}
