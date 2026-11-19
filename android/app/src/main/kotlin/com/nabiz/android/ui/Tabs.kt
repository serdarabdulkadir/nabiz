package com.nabiz.android.ui

import androidx.compose.ui.Alignment

import androidx.compose.foundation.layout.height

import androidx.compose.foundation.layout.fillMaxHeight

import androidx.compose.foundation.layout.IntrinsicSize

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
import com.nabiz.android.peer.MacService
import com.nabiz.android.peer.MacSource
import com.nabiz.android.service.MacCardModel
import com.nabiz.android.peer.Snapshot
import com.nabiz.android.stats.HistoryStore
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
    // Ayni satirdaki iki karo her zaman esit boyda.
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Space.md)) {
        a(Modifier.weight(1f).fillMaxHeight()); b(Modifier.weight(1f).fillMaxHeight())
    }
}

private fun thermalText(t: String?): String = when (t) {
    "normal" -> "Normal"; "warn" -> "Isınıyor"; "critical" -> "Kritik"; else -> none
}

private fun pressureText(p: String?): String? = when (p) {
    "normal" -> "Baskı normal"; "warn" -> "Baskı uyarı"; "critical" -> "Baskı kritik"; else -> null
}

@Composable
fun PhoneTab(s: Snapshot?, history: HistoryStore) {
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
        { m -> NetTile(s?.net?.down, s?.net?.up, m) },
    )
    Pair2(
        { m -> Tile("Termal", thermalText(s?.thermal), m) },
        { m -> Tile("Çalışma süresi", s?.uptime?.let { Format.uptime(it) } ?: none, m) },
    )
    val batH by history.phoneBattery.collectAsState()
    val memH by history.phoneMemory.collectAsState()
    Pair2(
        { m -> SparkTile("Pil", batH, batColor, m) },
        { m -> SparkTile("Bellek", memH, levelColor(memPct, 75, 90), m) },
    )
}

@Composable
fun MacTab(
    link: LinkState, onCmd: (String) -> Unit, history: HistoryStore,
    found: List<MacService> = emptyList(), pinnedId: String? = null, onConnect: (String) -> Unit = {}, onRescan: () -> Unit = {},
) {
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
        if (link.phase == LinkPhase.SEARCHING || link.phase == LinkPhase.IDLE) FoundList(found, pinnedId, onConnect, onRescan)
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
    val cpuH by history.macCpuSeries.collectAsState()
    val memH by history.macMemory.collectAsState()
    Pair2(
        { m -> SparkTile("CPU", cpuH, levelColor(cpu?.total, 75, 90), m) },
        { m -> SparkTile("Bellek", memH, levelColor(memPct, 75, 90), m) },
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

private fun sourceLabel(s: MacSource) = when (s) {
    MacSource.LAN -> "Yerel ağ"
    MacSource.HOTSPOT -> "Hotspot"
    MacSource.LAST -> "Son adres"
}

/** Bagli degilken bulunan Mac'ler; dokununca o Mac'e baglanir (pinliyse yalniz pinli Mac). */
@Composable
private fun FoundList(found: List<MacService>, pinnedId: String?, onConnect: (String) -> Unit, onRescan: () -> Unit) {
    val c = MaterialTheme.nabiz
    SectionLabel("Bulunan Mac'ler")
    Column(Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.group))) {
        if (found.isEmpty()) {
            Column(Modifier.fillMaxWidth().padding(Space.lg), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("Aranıyor…", style = NabizType.rowTitle, color = c.text)
                Text("Mac ve telefon aynı Wi‑Fi'da ya da Mac telefonun hotspot'unda olmalı", style = NabizType.caption, color = c.textSecondary)
            }
        } else found.forEach { m ->
            val ok = pinnedId == null || pinnedId == m.id
            Column(
                Modifier.fillMaxWidth().pressable(0.98f, ok) { onConnect(m.id) }.padding(horizontal = Space.lg, vertical = Space.md),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(m.name, style = NabizType.rowTitle, color = if (ok) c.text else c.textTertiary)
                Text((m.host.hostAddress ?: "") + ":" + m.port + " · " + sourceLabel(m.source), style = NabizType.caption, color = c.textSecondary)
            }
        }
    }
    TextButton(onClick = onRescan) { Text("Yeniden ara") }
}

private fun statusLine(l: LinkState): String = when (l.phase) {
    LinkPhase.IDLE -> "Başlatılıyor"
    LinkPhase.SEARCHING -> reasonText(l.reason, l.peerVersion) ?: "Mac aranıyor…"
    LinkPhase.CONNECTING -> "Bağlanılıyor" + (l.macName?.let { ": $it" } ?: "")
    LinkPhase.AWAIT_SAS -> "Eşleşme kodu onayı bekleniyor"
    LinkPhase.READY -> "Bağlı, ilk veri bekleniyor"
}

/** Halkali karonun yaninda duran Ag karosu: Mac'teki gibi ortali baslik, ortada iki satir hiz. */
@Composable
private fun NetTile(down: Long?, up: Long?, modifier: Modifier) {
    val c = MaterialTheme.nabiz
    Column(
        modifier.background(c.card, RoundedCornerShape(NabizShape.tile)).padding(vertical = Space.md, horizontal = Space.sm),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        Text("AĞ", style = NabizType.micro, color = c.textSecondary)
        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text("↓ " + (down?.let { Format.rate(it) } ?: none), style = NabizType.rowTitle, color = c.text, maxLines = 1)
            Text("↑ " + (up?.let { Format.rate(it) } ?: none), style = NabizType.rowTitle, color = c.textSecondary, maxLines = 1)
        }
        Text(" ", style = NabizType.caption)
    }
}
