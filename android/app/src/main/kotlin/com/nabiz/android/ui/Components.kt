package com.nabiz.android.ui

import androidx.compose.foundation.background
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.getValue
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

/** Anlam rengi yalniz kritik/uyari degerde; normalde vurgu rengi. */
@Composable
fun levelColor(pct: Int?, warnAt: Int, badAt: Int): Color = when {
    pct == null -> MaterialTheme.nabiz.textTertiary
    pct >= badAt -> MaterialTheme.nabiz.bad
    pct >= warnAt -> MaterialTheme.nabiz.warn
    else -> MaterialTheme.nabiz.accent
}

@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val c = MaterialTheme.nabiz
    val haptic = LocalHapticFeedback.current
    val pad = 3.dp
    BoxWithConstraints(modifier.fillMaxWidth().background(c.fill, CircleShape).padding(pad)) {
        val segW = maxWidth / options.size
        val x by animateDpAsState(segW * selected, Motion.spring(), label = "seg")
        Box(
            Modifier.offset(x = x).width(segW).height(36.dp)
                .shadow(2.dp, CircleShape, clip = false, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f))
                .background(if (c.dark) Color(0xFF636366) else c.card, CircleShape),
        )
        Row(Modifier.fillMaxWidth()) {
            options.forEachIndexed { i, label ->
                val on = i == selected
                val tint by animateColorAsState(if (on) c.text else c.textSecondary, Motion.spring(), label = "segText")
                Box(
                    Modifier.weight(1f).height(36.dp).pressable(0.96f) {
                        if (!on) {
                            haptic.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            onSelect(i)
                        }
                    },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(label, style = NabizType.rowTitle.copy(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium), color = tint)
                }
            }
        }
    }
}

/** Karo: kucuk baslik, buyuk deger, alt satir, istege bagli ince ilerleme cubugu. */
@Composable
fun Tile(
    title: String, value: String, modifier: Modifier = Modifier,
    sub: String? = null, bar: Int? = null, barColor: Color = MaterialTheme.nabiz.accent,
    content: (@Composable () -> Unit)? = null,
) {
    val c = MaterialTheme.nabiz
    Column(
        modifier.background(c.card, RoundedCornerShape(NabizShape.tile)).padding(Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.xs),
    ) {
        Text(title.uppercase(java.util.Locale.forLanguageTag("tr")), style = NabizType.micro, color = c.textSecondary)
        AnimatedNumber(value, NabizType.numLarge, c.text, Modifier.align(Alignment.Start))
        if (sub != null) Text(sub, style = NabizType.caption, color = c.textSecondary)
        if (bar != null) {
            Box(Modifier.fillMaxWidth().height(4.dp).background(c.fill, RoundedCornerShape(2.dp))) {
                Box(Modifier.fillMaxWidth(bar.coerceIn(0, 100) / 100f).fillMaxHeight().background(barColor, RoundedCornerShape(2.dp)))
            }
        }
        content?.invoke()
    }
}

/** Cekirdek cubuklari: P (performans) ve E (verimlilik) ayri gruplanir; grup bilgisi yoksa tek sira. */
@Composable
fun CoreBars(cores: List<Int>, perf: Int?, eff: Int?) {
    val c = MaterialTheme.nabiz
    val p = perf ?: 0
    val e = eff ?: 0
    val groups: List<Pair<String, List<Int>>> =
        // Mac (host_processor_info) once verimlilik (E), sonra performans (P) cekirdeklerini yollar.
        if (p > 0 && e > 0 && p + e <= cores.size) listOf("P" to cores.drop(e).take(p), "E" to cores.take(e))
        else listOf("" to cores)
    Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
        groups.forEach { (label, list) ->
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                if (label.isNotEmpty()) Text(label, style = NabizType.micro, color = c.textTertiary, modifier = Modifier.width(12.dp))
                list.forEach { v ->
                    Box(Modifier.weight(1f, fill = true).height(36.dp).background(c.fill, RoundedCornerShape(3.dp)), contentAlignment = Alignment.BottomCenter) {
                        Box(
                            Modifier.fillMaxWidth().fillMaxHeight(v.coerceIn(0, 100) / 100f)
                                .background(levelColor(v, 60, 85), RoundedCornerShape(3.dp)),
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(
        text.uppercase(java.util.Locale.forLanguageTag("tr")), style = NabizType.micro, color = MaterialTheme.nabiz.textSecondary,
        textAlign = TextAlign.Start, modifier = Modifier.padding(start = Space.lg, top = Space.sm),
    )
}
