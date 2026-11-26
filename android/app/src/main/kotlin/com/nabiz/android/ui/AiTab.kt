package com.nabiz.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.Canvas
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nabiz.android.peer.AiLimit
import com.nabiz.android.peer.AiProvider
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz
import kotlinx.coroutines.delay

@Composable
private fun providerColor(id: String): Color = when (id) {
    "claude" -> Color(0xFFD97757)
    "codex" -> MaterialTheme.nabiz.text
    "cursor" -> Color(0xFF6B8CFA)
    else -> MaterialTheme.nabiz.textSecondary
}

/** Mac'ten gelen AI kullanim limitleri (yalniz gosterim). Karta dokununca tum limitler acilir. */
@Composable
fun AiTab(providers: List<AiProvider>, syncing: Boolean = false) {
    // Geri sayimlar ve "x dk once" metni telefonun yerel saatiyle kendiliginden ilerler.
    var now by remember { mutableLongStateOf(System.currentTimeMillis() / 1000) }
    LaunchedEffect(Unit) { while (true) { delay(5_000); now = System.currentTimeMillis() / 1000 } }
    providers.forEach { AiCard(it, now, syncing) }   // her hesap ayri kart
}

@Composable
private fun AiCard(p: AiProvider, now: Long, syncing: Boolean) {
    val c = MaterialTheme.nabiz
    var open by rememberSaveable(p.hesapId) { mutableStateOf(false) }
    val front = AiFormat.frontLimits(p.limitler)
    val tempo = AiFormat.tempo(p)
    val full = front.any { it.yuzde >= 100 }
    Column(
        Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.tile)).pressable(0.98f) { open = !open }.padding(Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Logo(p)
                    Text(p.ad, style = NabizType.rowTitle, fontWeight = FontWeight.Bold, color = c.text, maxLines = 1)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
                    p.plan?.let { Text(it.uppercase(java.util.Locale.forLanguageTag("tr")), style = NabizType.micro, color = c.textSecondary, maxLines = 1) }
                    p.hesap?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = NabizType.micro, color = c.textSecondary, maxLines = 1,
                            modifier = Modifier.background(c.fill, CircleShape).padding(horizontal = Space.sm, vertical = 2.dp))
                    }
                }
                if (tempo != null) {
                    val tone = if (full) c.bad else Color(0xFF8E6BF0)
                    Text(tempo, style = NabizType.micro, color = tone,
                        modifier = Modifier.background(tone.copy(alpha = 0.14f), CircleShape).padding(horizontal = Space.sm, vertical = 3.dp))
                } else p.notu?.let { Text(it, style = NabizType.caption, color = c.textSecondary) }
            }
            // Iki yuva her zaman ayni genislikte; tek limit varsa ikinci yuva bos kalir.
            for (i in 0..1) {
                val l = front.getOrNull(i)
                if (l != null) LimitRing(l, now) else Spacer(Modifier.width(76.dp))
            }
        }
        p.sorun?.let { Text(it, style = NabizType.caption, color = c.warn) }
        if (open && p.limitler.isNotEmpty()) {
            Column {
                p.limitler.forEach { l ->
                    Row(Modifier.fillMaxWidth().padding(vertical = Space.xs), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(l.ad, style = NabizType.body, color = c.text)
                            AiFormat.resetText(l.sifirlanma, now)?.let { Text(it, style = NabizType.caption, color = c.textSecondary) }
                        }
                        Text("%${l.yuzde}", style = NabizType.ringValue, color = levelColor(l.yuzde, 75, 90))
                    }
                }
            }
        }
        val updated = AiFormat.updatedText(p.guncel, now)
        if (updated != null || syncing) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.xs)) {
                if (syncing) CircularProgressIndicator(Modifier.size(10.dp), strokeWidth = 1.5.dp, color = c.textTertiary)
                Text(
                    listOfNotNull(updated, if (syncing) "yenileniyor" else null).joinToString(" · "),
                    style = NabizType.caption, color = c.textTertiary,
                )
            }
        }
    }
}

/** Saglayici baş harfli kucuk daire logo (gercek logo yok). */
@Composable
private fun Logo(p: AiProvider) {
    val c = MaterialTheme.nabiz
    val bg = providerColor(p.id)
    val fg = if (p.id == "codex") c.bg else Color.White
    Box(Modifier.size(24.dp).background(bg, CircleShape), contentAlignment = Alignment.Center) {
        Text(p.ad.take(1).uppercase(), style = NabizType.micro, fontWeight = FontWeight.Bold, color = fg)
    }
}

private val RingBlue = Color(0xFF5B8DEF)
private val RingPurple = Color(0xFF9B6BFF)

/** 270 derece halka (aciklik altta), ortada yuzde; altinda limit adi ve sifirlanmaya kalan sure. %90+ kirmizi. */
@Composable
private fun LimitRing(l: AiLimit, now: Long) {
    val c = MaterialTheme.nabiz
    val f by animateFloatAsState((l.yuzde / 100f).coerceIn(0f, 1f), Motion.spring(), label = "aiRing")
    val hot = l.yuzde >= 90
    val track = c.fill
    val bad = c.bad
    Column(Modifier.width(76.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.size(64.dp)) {
                val w = 6.dp.toPx()
                val arc = Size(size.width - w, size.height - w)
                val tl = Offset(w / 2, w / 2)
                rotate(135f) {
                    drawArc(track, 0f, 270f, false, tl, arc, style = Stroke(w, cap = StrokeCap.Round))
                    if (f > 0f) {
                        val brush = if (hot) Brush.linearGradient(listOf(bad, bad))
                        else Brush.sweepGradient(0f to RingBlue, 0.75f to RingPurple, 1f to RingPurple)
                        drawArc(brush, 0f, 270f * f, false, tl, arc, style = Stroke(w, cap = StrokeCap.Round))
                    }
                }
            }
            Text("%${l.yuzde}", style = NabizType.ringValue, color = if (hot) c.bad else c.text)
        }
        Text(l.ad, style = NabizType.micro, color = c.textSecondary, maxLines = 1, textAlign = TextAlign.Center)
        Text(AiFormat.untilReset(l.sifirlanma, now) ?: " ", style = NabizType.caption, color = c.textSecondary, maxLines = 1, textAlign = TextAlign.Center)
    }
}
