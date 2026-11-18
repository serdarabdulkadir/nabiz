package com.nabiz.android.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

/** ORBIO Android paleti: sade monokrom + tek vurgu. Acik palet ORBIO'dan, koyu palet ayni dilde ters cevrilmistir. */
class NabizColors(
    val bg: Color, val card: Color, val fill: Color, val separator: Color,
    val text: Color, val textSecondary: Color, val textTertiary: Color,
    val accent: Color, val onAccent: Color,
    val good: Color, val warn: Color, val bad: Color,
    val dark: Boolean,
)

private val LightPalette = NabizColors(
    bg = Color(0xFFF2F2F7), card = Color(0xFFFFFFFF), fill = Color(0xFFE9E9EE), separator = Color(0x80C6C6C8),
    text = Color(0xFF000000), textSecondary = Color(0x993C3C43), textTertiary = Color(0x4D3C3C43),
    accent = Color(0xFF000000), onAccent = Color(0xFFFFFFFF),
    good = Color(0xFF34C759), warn = Color(0xFFFF9500), bad = Color(0xFFFF3B30),
    dark = false,
)

private val DarkPalette = NabizColors(
    bg = Color(0xFF000000), card = Color(0xFF1C1C1E), fill = Color(0xFF2C2C2E), separator = Color(0x99545458),
    text = Color(0xFFFFFFFF), textSecondary = Color(0x99EBEBF5), textTertiary = Color(0x4DEBEBF5),
    accent = Color(0xFFFFFFFF), onAccent = Color(0xFF000000),
    good = Color(0xFF30D158), warn = Color(0xFFFF9F0A), bad = Color(0xFFFF453A),
    dark = true,
)

val LocalNabizColors = staticCompositionLocalOf { LightPalette }

/** Esmerkezli koseler: ic oge 12, grup 18, buyuk karo 22. Segment/hap kapsul. */
object NabizShape {
    val sm = 8.dp
    val md = 12.dp
    val item = 12.dp
    val group = 18.dp
    val tile = 22.dp
    val lg = 22.dp
}

/** Bosluk ritmi: 4 tabanli. */
object Space {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
}

object NabizType {
    private const val TNUM = "tnum"
    val pageTitle = TextStyle(fontSize = 34.sp, lineHeight = 41.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp)
    val rowTitle = TextStyle(fontSize = 16.sp, lineHeight = 21.sp, fontWeight = FontWeight.Medium)
    val body = TextStyle(fontSize = 15.sp, lineHeight = 21.sp, fontWeight = FontWeight.Normal)
    val caption = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal, fontFeatureSettings = TNUM)
    val micro = TextStyle(fontSize = 13.sp, lineHeight = 16.sp, fontWeight = FontWeight.Normal, letterSpacing = (-0.1).sp)
    val numLarge = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Default, fontFeatureSettings = TNUM)
    val ringValue = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Default, fontFeatureSettings = TNUM)
    val code = TextStyle(fontSize = 36.sp, lineHeight = 44.sp, fontWeight = FontWeight.Bold, letterSpacing = 6.sp, fontFeatureSettings = TNUM)
}

val MaterialTheme.nabiz: NabizColors
    @Composable get() = LocalNabizColors.current

@Composable
fun NabizTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val p = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(
            primary = p.accent, onPrimary = p.onAccent, background = p.bg, onBackground = p.text,
            surface = p.card, onSurface = p.text, surfaceVariant = p.fill, onSurfaceVariant = p.textSecondary,
            outline = p.separator, error = p.bad,
        )
    } else {
        lightColorScheme(
            primary = p.accent, onPrimary = p.onAccent, background = p.bg, onBackground = p.text,
            surface = p.card, onSurface = p.text, surfaceVariant = p.fill, onSurfaceVariant = p.textSecondary,
            outline = p.separator, error = p.bad,
        )
    }
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            val ctl = WindowCompat.getInsetsController(window, view)
            ctl.isAppearanceLightStatusBars = !dark
            ctl.isAppearanceLightNavigationBars = !dark
        }
    }
    CompositionLocalProvider(LocalNabizColors provides p) {
        MaterialTheme(
            colorScheme = scheme,
            typography = Typography(),
            shapes = Shapes(
                small = RoundedCornerShape(NabizShape.sm),
                medium = RoundedCornerShape(NabizShape.md),
                large = RoundedCornerShape(NabizShape.lg),
            ),
            content = content,
        )
    }
}
