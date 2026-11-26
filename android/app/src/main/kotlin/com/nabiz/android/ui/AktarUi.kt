package com.nabiz.android.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nabiz.android.R
import com.nabiz.android.aktar.AktarText
import com.nabiz.android.aktar.TransferInfo
import com.nabiz.android.aktar.TransferStatus
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkState
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

/** Yuvarlak Mac avatari; `progress` (0..1) verilirse cevresinde ilerleme halkasi. */
@Composable
fun MacAvatar(size: Int, progress: Float?, modifier: Modifier = Modifier) {
    val c = MaterialTheme.nabiz
    val p by animateFloatAsState(progress ?: 0f, Motion.spring(), label = "ring")
    Box(modifier.size(size.dp), contentAlignment = Alignment.Center) {
        Box(Modifier.size((size - 10).dp).background(c.fill, CircleShape), contentAlignment = Alignment.Center) {
            androidx.compose.foundation.Image(
                painterResource(R.drawable.ic_aktar_mac), null, Modifier.size((size / 2.4f).dp), colorFilter = ColorFilter.tint(c.text),
            )
        }
        if (progress != null) {
            Canvas(Modifier.size(size.dp)) {
                val w = 3.dp.toPx()
                val inset = w / 2
                val s = Size(this.size.width - w, this.size.height - w)
                drawArc(c.separator, 0f, 360f, false, Offset(inset, inset), s, style = Stroke(w))
                drawArc(c.accent, -90f, 360f * p, false, Offset(inset, inset), s, style = Stroke(w, cap = StrokeCap.Round))
            }
        }
    }
}

/** Paylas sayfasi: alttan acilan Apple vari sayfa. Arka plan dokunusu kapatir. */
@Composable
fun ShareSheet(
    count: Int, totalBytes: Long?, macName: String?, ready: Boolean, enabled: Boolean, sending: Boolean,
    onSend: () -> Unit, onRetry: () -> Unit, onDismiss: () -> Unit,
) {
    val c = MaterialTheme.nabiz
    Box(
        Modifier.fillMaxSize().clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Column(
            Modifier.fillMaxWidth()
                .background(c.card, RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { }
                .navigationBarsPadding().padding(start = Space.lg, end = Space.lg, top = Space.sm, bottom = Space.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Space.xs),
        ) {
            Box(Modifier.width(36.dp).height(5.dp).background(c.fill, CircleShape))
            Text(AktarText.shareTitle(count), style = NabizType.rowTitle.copy(fontSize = 17.sp), color = c.text, modifier = Modifier.padding(top = Space.md))
            Text(AktarText.shareSub(totalBytes), style = NabizType.caption, color = c.textSecondary)
            Box(Modifier.height(Space.md))
            when {
                !enabled -> Note("Aktar kapalı", "Nabız ayarlarından aç")
                !ready -> {
                    Note("Mac bulunamadı", "Mac'te Nabız açık ve aynı Wi-Fi'de olmalı")
                    Text(
                        "Yeniden ara", style = NabizType.rowTitle, color = c.text,
                        modifier = Modifier.padding(top = Space.sm).background(c.fill, CircleShape).pressable { onRetry() }.padding(horizontal = Space.lg, vertical = Space.sm),
                    )
                }
                else -> Column(
                    Modifier.pressable(0.95f, !sending) { onSend() }.padding(Space.sm),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.xs),
                ) {
                    MacAvatar(72, if (sending) 1f else null)
                    Text(macName ?: "Mac", style = NabizType.rowTitle, color = c.text)
                    Text(if (sending) "Gönderiliyor" else "Dokun, gönder", style = NabizType.caption, color = c.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun Note(title: String, sub: String) {
    val c = MaterialTheme.nabiz
    Column(Modifier.padding(vertical = Space.sm), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = NabizType.rowTitle, color = c.text, textAlign = TextAlign.Center)
        Text(sub, style = NabizType.caption, color = c.textSecondary, textAlign = TextAlign.Center)
    }
}

/** Ana ekran Aktar sekmesi: Mac avatari + Mac'e gonder, altinda son aktarimlar. */
@Composable
fun AktarTab(
    link: LinkState, enabled: Boolean, transfers: List<TransferInfo>, onPick: () -> Unit, onCancel: (String) -> Unit,
    onAccept: (String) -> Unit, onReject: (String) -> Unit,
) {
    val c = MaterialTheme.nabiz
    val ready = link.phase == LinkPhase.READY
    val active = transfers.firstOrNull { it.status == TransferStatus.ACTIVE }
    Column(
        Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.tile)).padding(Space.lg),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        MacAvatar(78, active?.let { it.percent / 100f })
        Text(link.macName ?: "Mac", style = NabizType.rowTitle, color = c.text)
        Text(
            when {
                !enabled -> "Aktar kapalı: Ayarlar'dan aç"
                ready -> "Bağlı · dosya göndermeye hazır"
                else -> "Mac bulunamadı"
            },
            style = NabizType.caption, color = c.textSecondary,
        )
        val can = ready && enabled
        Text(
            "Mac'e gönder", style = NabizType.rowTitle, color = if (can) c.onAccent else c.textTertiary,
            modifier = Modifier.padding(top = Space.sm)
                .background(if (can) c.accent else c.fill, CircleShape)
                .pressable(0.96f, can) { onPick() }.padding(horizontal = Space.xl, vertical = Space.md),
        )
    }
    SectionLabel("Son aktarımlar")
    if (transfers.isEmpty()) {
        Text("Henüz aktarım yok. Galeri ya da Dosyalar'dan Paylaş > Nabız'ı seç.", style = NabizType.caption, color = c.textSecondary, modifier = Modifier.padding(horizontal = Space.lg))
    } else {
        Column(Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.group))) {
            transfers.forEachIndexed { i, t ->
                if (i > 0) Box(Modifier.fillMaxWidth().padding(start = Space.lg).height(0.5.dp).background(c.separator))
                TransferRow(t, onCancel, onAccept, onReject)
            }
        }
    }
}

@Composable
private fun TransferRow(t: TransferInfo, onCancel: (String) -> Unit, onAccept: (String) -> Unit, onReject: (String) -> Unit) {
    val c = MaterialTheme.nabiz
    Column(Modifier.fillMaxWidth().padding(horizontal = Space.lg, vertical = Space.md), verticalArrangement = Arrangement.spacedBy(Space.xs)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(t.title, style = NabizType.rowTitle, color = c.text, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                Text(AktarText.subtitle(t), style = NabizType.caption, color = c.textSecondary, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            }
            when {
                t.status == TransferStatus.OFFERED -> Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Text("Reddet", style = NabizType.rowTitle, color = c.textSecondary, modifier = Modifier.pressable { onReject(t.aid) }.padding(Space.sm))
                    Text("Kabul et", style = NabizType.rowTitle, color = c.text, modifier = Modifier.pressable { onAccept(t.aid) }.padding(Space.sm))
                }
                t.running -> Text("İptal", style = NabizType.rowTitle, color = c.textSecondary, modifier = Modifier.pressable { onCancel(t.aid) }.padding(Space.sm))
                else -> Text(
                    AktarText.statusLabel(t.status), style = NabizType.caption,
                    color = when (t.status) { TransferStatus.DONE -> c.good; TransferStatus.FAILED -> c.bad; else -> c.textSecondary },
                )
            }
        }
        if (t.status == TransferStatus.ACTIVE) {
            Box(Modifier.fillMaxWidth().height(4.dp).background(c.fill, RoundedCornerShape(2.dp))) {
                Box(Modifier.fillMaxWidth(t.percent / 100f).height(4.dp).background(c.accent, RoundedCornerShape(2.dp)))
            }
        }
    }
}
