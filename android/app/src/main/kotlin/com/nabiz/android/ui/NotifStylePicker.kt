package com.nabiz.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.nabiz.android.peer.BatteryStats
import com.nabiz.android.peer.CpuStats
import com.nabiz.android.peer.DiskStats
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkState
import com.nabiz.android.peer.MemStats
import com.nabiz.android.peer.NetStats
import com.nabiz.android.peer.PeerMessage
import com.nabiz.android.peer.Snapshot
import com.nabiz.android.service.MacCardModel
import com.nabiz.android.service.MacCardNotification
import com.nabiz.android.service.NotifStyle
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

private val sampleState = LinkState(
    phase = LinkPhase.READY, macName = "MacBook",
    macSnap = Snapshot(
        1, cpu = CpuStats(23), mem = MemStats(61, 100), disk = DiskStats(88, 100),
        battery = BatteryStats(31, false, minutes = 200), net = NetStats(20_000, 1_200_000), gpu = 12, uptime = 11_000,
    ),
    macState = PeerMessage.MacState(kilitli = false, ekranKapali = false, uykuyaGidiyor = false),
)

/** Bildirim tasarimi secici: her stil icin bildirimi taklit eden mini onizleme. */
@Composable
fun NotifStylePicker(selected: NotifStyle, onSelect: (NotifStyle) -> Unit) {
    val c = MaterialTheme.nabiz
    Column(verticalArrangement = Arrangement.spacedBy(Space.md)) {
        NotifStyle.entries.forEach { st ->
            val on = st == selected
            Column(
                Modifier.fillMaxWidth()
                    .background(c.card, RoundedCornerShape(NabizShape.group))
                    .border(BorderStroke(if (on) 2.dp else 0.dp, if (on) c.accent else Color.Transparent), RoundedCornerShape(NabizShape.group))
                    .pressable { onSelect(st) }
                    .padding(Space.lg),
                verticalArrangement = Arrangement.spacedBy(Space.sm),
            ) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(st.label + if (st == NotifStyle.CANLI) " (varsayılan)" else "", style = NabizType.rowTitle, color = c.text)
                    if (on) Text("Seçili", style = NabizType.caption, color = c.accent)
                }
                Text(st.description, style = NabizType.caption, color = c.textSecondary)
                MiniNotification(MacCardModel.from(sampleState, st))
            }
        }
    }
}

@Composable
private fun MiniNotification(m: MacCardModel) {
    val c = MaterialTheme.nabiz
    Column(
        Modifier.fillMaxWidth().background(c.fill, RoundedCornerShape(NabizShape.item)).padding(Space.md),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(m.title, style = NabizType.rowTitle, color = c.text)
        Text(m.text, style = NabizType.caption, color = c.textSecondary)
        m.bigText?.let { Text(it, style = NabizType.caption, color = c.textSecondary) }
        if (m.progress != null && m.segments.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().padding(top = Space.xs).height(6.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                var start = 0
                m.segments.forEach { seg ->
                    val filled = ((m.progress - start).toFloat() / seg.length).coerceIn(0f, 1f)
                    val col = Color(MacCardNotification.toneColor(seg.tone))
                    Row(Modifier.weight(seg.length.toFloat()).fillMaxHeight().background(col.copy(alpha = col.alpha * 0.3f), RoundedCornerShape(3.dp))) {
                        if (filled > 0f) Box(Modifier.weight(filled).fillMaxHeight().background(col, RoundedCornerShape(3.dp)))
                        if (filled < 1f) Box(Modifier.weight(1f - filled).fillMaxHeight())
                    }
                    start += seg.length
                }
            }
        }
        if (m.actions.isNotEmpty()) {
            Row(Modifier.padding(top = Space.xs), horizontalArrangement = Arrangement.spacedBy(Space.md), verticalAlignment = Alignment.CenterVertically) {
                m.actions.forEach { Text(it.label, style = NabizType.caption, color = c.accent) }
            }
        }
    }
}
