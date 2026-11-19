package com.nabiz.android.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.nabiz.android.stats.HistoryPoint
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

/** Son 10 dk sparkline karosu: ince cizgi, alan dolgusu, son nokta vurgulu. Renk cagirandan (tema esik token'lari). */
@Composable
fun SparkTile(title: String, points: List<HistoryPoint>, color: Color, modifier: Modifier = Modifier) {
    val c = MaterialTheme.nabiz
    Column(
        modifier.background(c.card, RoundedCornerShape(NabizShape.tile)).padding(Space.lg),
        verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(Space.xs),
    ) {
        Text(title.uppercase(java.util.Locale.forLanguageTag("tr")), style = NabizType.micro, color = c.textSecondary)
        Canvas(Modifier.fillMaxWidth().height(48.dp)) {
            if (points.size < 2) return@Canvas
            val t0 = points.first().atMs
            val span = (points.last().atMs - t0).coerceAtLeast(1L).toFloat()
            val pad = 4.dp.toPx()
            val h = size.height - 2 * pad
            fun pos(p: HistoryPoint) = Offset(
                (p.atMs - t0) / span * size.width,
                pad + h * (1f - p.value.coerceIn(0, 100) / 100f),
            )
            val line = Path()
            val fill = Path()
            points.forEachIndexed { i, p ->
                val o = pos(p)
                if (i == 0) { line.moveTo(o.x, o.y); fill.moveTo(o.x, size.height); fill.lineTo(o.x, o.y) } else { line.lineTo(o.x, o.y); fill.lineTo(o.x, o.y) }
            }
            val last = pos(points.last())
            fill.lineTo(last.x, size.height); fill.close()
            drawPath(fill, color.copy(alpha = 0.15f))
            drawPath(line, color, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
            drawCircle(c.card, 5.dp.toPx(), last)
            drawCircle(color, 3.5.dp.toPx(), last)
        }
        Text("Son 10 dk", style = NabizType.caption, color = c.textTertiary)
    }
}
