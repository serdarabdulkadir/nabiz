package com.nabiz.android.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer

/** Ortak hareket egrisi (Mac: spring 0.35 / 0.82). */
object Motion {
    const val DAMPING = 0.82f
    val stiffness = Spring.StiffnessMediumLow
    fun <T> spring() = spring<T>(dampingRatio = DAMPING, stiffness = stiffness)
}

/** Basilabilir oge: basinca spring ile kucuk olcek, ripple yok. */
@Composable
fun Modifier.pressable(scale: Float = 0.97f, enabled: Boolean = true, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed && enabled) scale else 1f, Motion.spring(), label = "press")
    return this
        .graphicsLayer { scaleX = s; scaleY = s }
        .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
}
