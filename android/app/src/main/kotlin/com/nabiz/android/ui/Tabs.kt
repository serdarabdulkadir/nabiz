package com.nabiz.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkReason
import com.nabiz.android.peer.LinkState
import com.nabiz.android.peer.LinkVia
import com.nabiz.android.service.MacCardModel
import com.nabiz.android.peer.Snapshot
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz
import androidx.compose.material3.TextButton
import java.text.DateFormat
import java.util.Date

private val none = Format.NONE

fun viaLabel(v: LinkVia): String = if (v == LinkVia.REMOTE) "Uzak (Tailscale)" else "Yerel ağ"

@Composable
private fun Pair2(a: @Composable (Modifier) -> Unit, b: @Composable (Modifier) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        a(Modifier.weight(1f)); b(Modifier.weight(1f))
    }
}

private fun thermalText(t: String?): String = when (t) {
    "normal" -> "Normal"; "warn" -> "Isınıyor"; "critical" -> "Kritik"; else -> none
}

private fun pressureText(p: String?): String? = when (p) {
    "normal" -> "Baskı normal"; "warn" -> "Baskı uyarı"; "critical" -> "Baskı kritik"; else -> null
}

@Composable
fun PhoneTab(s: Snapshot?) {
    val c = MaterialTheme.nabiz
    val bat = s?.battery
    val mem = s?.mem
    val disk = s?.disk
    val memPct = mem?.let { Format.percent(it.used, it.total) }
    val diskPct = disk?.let { Format.percent(it.used, it.total) }
    val batColor = if ((bat?.level ?: 100) <= 20 && bat?.charging != true) c.bad else if (bat?.charging == true) c.good else c.accent
    Pair2(
        { m ->
            RingTile(
                "Pil", bat?.level?.let { it / 100f }, bat?.let { "%${it.level}" } ?: none, batColor, m,
                detail = bat?.let { (if (it.charging) "Şarj oluyor" else "Şarjda değil") + (it.temp?.let { t -> " · " + Format.temp(t) } ?: "") },
            )
        },
        { m -> RingTile("Bellek", memPct?.let { it / 100f }, memPct?.let { "%$it" } ?: none, levelColor(memPct, 75, 90), m, detail = mem?.let { Format.bytes(it.used) + " / " + Format.bytes(it.total) }) },
    )
    Pair2(
        { m -> RingTile("Depolama", diskPct?.let { it / 100f }, diskPct?.let { "%$it" } ?: none, levelColor(diskPct, 75, 90), m, detail = disk?.let { Format.bytes(it.used) + " / " + Format.bytes(it.total) }) },
        { m -> Tile("Ağ", s?.net?.let { "↓ " + Format.rate(it.down) } ?: none, m, sub = s?.net?.let { "↑ " + Format.rate(it.up) }) },
    )
    Pair2(
        { m -> Tile("Termal", thermalText(s?.thermal), m) },
        { m -> Tile("Çalışma süresi", s?.uptime?.let { Format.uptime(it) } ?: none, m) },
    )
}

@Composable
fun MacTab(link: LinkState, onCmd: (String) -> Unit) {
    val c = MaterialTheme.nabiz
    val s = link.macSnap
    if (link.phase != LinkPhase.READY && link.reason == LinkReason.SLEEPING) {
        Column(
            Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.tile)).padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            Text(MacCardModel.sleepingText(link.lastSeenAt), style = NabizType.rowTitle, color = c.text)
            Text("Uyanınca otomatik bağlanır", style = NabizType.caption, color = c.textSecondary)
        }
        return
    }
    if (link.phase != LinkPhase.READY || s == null) {
        Column(
            Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.tile)).padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            Text("Mac'te Nabız açık ve aynı Wi-Fi'de olmalı", style = NabizType.rowTitle, color = c.text)
            Text(statusLine(link), style = NabizType.caption, color = c.textSecondary)
        }
        return
    }
    val cpu = s.cpu
    val mem = s.mem
    val memPct = mem?.let { Format.percent(it.used, it.total) }
    val disk = s.disk
    val diskPct = disk?.let { Format.percent(it.used, it.total) }
    val b = s.battery
    val bColor = if ((b?.level ?: 100) <= 20 && b?.charging != true) c.bad else if (b?.charging == true) c.good else c.accent
    Pair2(
        { m -> RingTile("CPU", cpu?.total?.let { it / 100f }, cpu?.let { "%${it.total}" } ?: none, levelColor(cpu?.total, 75, 90), m, detail = link.macName) },
        { m -> RingTile("Bellek", memPct?.let { it / 100f }, memPct?.let { "%$it" } ?: none, levelColor(memPct, 75, 90), m, detail = mem?.let { Format.bytes(it.used) + " / " + Format.bytes(it.total) }) },
    )
    Pair2(
        { m -> RingTile("Disk", diskPct?.let { it / 100f }, diskPct?.let { "%$it" } ?: none, levelColor(diskPct, 75, 90), m, detail = disk?.let { Format.bytes(it.used) + " / " + Format.bytes(it.total) }) },
        { m ->
            RingTile(
                "Pil", b?.level?.let { it / 100f }, b?.let { "%${it.level}" } ?: none, bColor, m,
                detail = b?.let { (if (it.charging) "Şarj oluyor" else "Pilde") + (it.minutes?.let { mn -> " · ${mn} dk" } ?: "") },
            )
        },
    )
    if (cpu != null && cpu.cores.isNotEmpty()) {
        Tile(
            "Çekirdekler", "%${cpu.total}", Modifier.fillMaxWidth(),
            sub = if (link.macState?.kilitli == true) "Kilitli" else null,
            content = { CoreBars(cpu.cores, cpu.perfCores, cpu.effCores) },
        )
    }
    Pair2(
        { m -> Tile("GPU", s.gpu?.let { "%$it" } ?: none, m, bar = s.gpu, barColor = levelColor(s.gpu, 70, 90)) },
        { m -> Tile("Çalışma süresi", s.uptime?.let { Format.uptime(it) } ?: none, m) },
    )
    Tile("Ağ", s.net?.let { "↓ " + Format.rate(it.down) } ?: none, Modifier.fillMaxWidth(), sub = s.net?.let { "↑ " + Format.rate(it.up) })
    Text(
        "Son güncelleme " + DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(link.macSnapAt)) + " · " + viaLabel(link.via),
        style = NabizType.caption, color = c.textTertiary,
    )
    Row(horizontalArrangement = Arrangement.spacedBy(Space.sm)) {
        MacCardModel.actionsFor(link).forEach { a -> Text(a.label, style = NabizType.rowTitle, color = c.text, modifier = Modifier.background(c.card, CircleShape).pressable { onCmd(a.eylem) }.padding(horizontal = Space.lg, vertical = Space.sm)) }
    }
}

private fun statusLine(l: LinkState): String = when (l.phase) {
    LinkPhase.IDLE -> "Başlatılıyor"
    LinkPhase.SEARCHING -> reasonText(l.reason) ?: "Mac aranıyor…"
    LinkPhase.CONNECTING -> "Bağlanılıyor" + (l.macName?.let { ": $it" } ?: "")
    LinkPhase.AWAIT_SAS -> "Eşleşme kodu onayı bekleniyor"
    LinkPhase.READY -> "Bağlı, ilk veri bekleniyor"
}
