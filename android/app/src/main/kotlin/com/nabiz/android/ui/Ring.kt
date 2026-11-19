package com.nabiz.android.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

/** Halka: iz rengi fill, 5dp yuvarlak uclu yay; deger degisince spring ile dolar. */
@Composable
fun Ring(fraction: Float?, color: Color, modifier: Modifier = Modifier, content: @Composable () -> Unit = {}) {
    val track = MaterialTheme.nabiz.fill
    val f by animateFloatAsState((fraction ?: 0f).coerceIn(0f, 1f), Motion.spring(), label = "ring")
    Box(modifier.size(60.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(60.dp)) {
            val w = 5.dp.toPx()
            val inset = w / 2
            val arc = Size(size.width - w, size.height - w)
            drawArc(track, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(w))
            if (f > 0.001f) {
                rotate(-90f) {
                    val brush = Brush.sweepGradient(
                        0f to color.copy(alpha = 0.7f),
                        f.coerceAtLeast(0.02f) to color,
                        1f to color,
                    )
                    drawArc(brush, 0f, 360f * f, false, Offset(inset, inset), arc, style = Stroke(w, cap = StrokeCap.Round))
                }
            }
        }
        content()
    }
}

/** Rakam degisince dikey kayarak gecer. */
@Composable
fun AnimatedNumber(text: String, style: androidx.compose.ui.text.TextStyle, color: Color, modifier: Modifier = Modifier) {
    AnimatedContent(
        targetState = text, modifier = modifier,
        transitionSpec = {
            (slideInVertically(Motion.spring()) { it / 2 } + fadeIn(Motion.spring()))
                .togetherWith(slideOutVertically(Motion.spring()) { -it / 2 } + fadeOut(Motion.spring()))
                .using(SizeTransform(clip = false))
        },
        label = "num",
    ) { t -> Text(t, style = style, color = color, textAlign = TextAlign.Center, maxLines = 1) }
}

/** Mac RingTile karsiligi: baslik, halka (ortada deger), alt satir. */
@Composable
fun RingTile(
    title: String, fraction: Float?, value: String, color: Color, modifier: Modifier = Modifier,
    detail: String? = null,
) {
    val c = MaterialTheme.nabiz
    Column(
        modifier.background(c.card, RoundedCornerShape(NabizShape.tile)).padding(vertical = Space.md, horizontal = Space.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        Text(title.uppercase(java.util.Locale.forLanguageTag("tr")), style = NabizType.micro, color = c.textSecondary)
        Ring(fraction, color) { AnimatedNumber(value, NabizType.ringValue, if (fraction == null) c.textTertiary else color) }
        Text(detail ?: " ", style = NabizType.caption, color = c.textSecondary, maxLines = 1, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
    }
}
