package com.nabiz.android.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.ui.Alignment
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import com.nabiz.android.alerts.AlertRule
import com.nabiz.android.alerts.AlertStore
import com.nabiz.android.alerts.RuleConfig
import com.nabiz.android.alerts.Subject
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.nabiz.android.phone.ShareKey
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.nabiz.android.ui.theme.NabizShape
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz

@Composable
fun SettingsScreen(vm: MainViewModel, pinnedName: String?, link: LinkState, onUnpair: () -> Unit, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val c = MaterialTheme.nabiz
    var confirm by remember { mutableStateOf(false) }
    val style by vm.notifStyle.collectAsStateWithLifecycle()
    var remote by rememberSaveable { mutableStateOf(vm.remoteAddress()) }
    var saved by remember { mutableStateOf(false) }
    var probe by remember { mutableStateOf<String?>(null) }
    val share by vm.shareFlags.collectAsStateWithLifecycle()
    val grants by vm.systemGrants.collectAsStateWithLifecycle()
    var pendingKey by remember { mutableStateOf<ShareKey?>(null) }
    var deniedKey by remember { mutableStateOf<ShareKey?>(null) }
    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { res ->
        val key = pendingKey
        pendingKey = null
        if (key != null) {
            // Arama kaydi izni (gelen numara) istenir ama zorunlu degil; zorunlu izinler `requiredPermissions`.
            if (requiredPermissions(key).all { ContextCompat.checkSelfPermission(ctx, it) == PackageManager.PERMISSION_GRANTED }) { deniedKey = null; vm.setShare(key, true) } else deniedKey = key
            vm.refreshShare()
        }
    }
    // Sistem ayarindan donunce (bildirim erisimi, uygulama izinleri) durum yeniden okunur.
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner) {
        val obs = LifecycleEventObserver { _, e -> if (e == Lifecycle.Event.ON_RESUME) vm.refreshShare() }
        owner.lifecycle.addObserver(obs)
        onDispose { owner.lifecycle.removeObserver(obs) }
    }
    fun toggleShare(key: ShareKey, on: Boolean) {
        deniedKey = null
        if (!on) { vm.setShare(key, false); return }
        if (key == ShareKey.BILDIRIMLER) {
            vm.setShare(key, true)
            if (!grants.bildirimErisimi) BackgroundAccess.openNotificationListenerSettings(ctx)
            return
        }
        val perms = runtimePermissions(key)
        if (perms.all { ContextCompat.checkSelfPermission(ctx, it) == PackageManager.PERMISSION_GRANTED }) vm.setShare(key, true)
        else { pendingKey = key; permLauncher.launch(perms) }
    }
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(Space.lg),
        verticalArrangement = Arrangement.spacedBy(Space.md),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("Ayarlar", style = NabizType.pageTitle, color = c.text)
            Text(
                "Kapat", style = NabizType.rowTitle, color = c.textSecondary,
                modifier = Modifier.pressable { onBack() }.padding(horizontal = Space.md, vertical = Space.sm),
            )
        }
        SectionLabel("Eşleşme")
        Group {
            Row2("Eşleşmeyi unut", pinnedName?.let { "Eşleşik Mac: $it" } ?: "Eşleşik Mac yok", enabled = pinnedName != null) { confirm = true }
        }
        SectionLabel("Uzak bağlantı")
        Column(
            Modifier.fillMaxWidth().background(c.card, RoundedCornerShape(NabizShape.group)).padding(Space.lg),
            verticalArrangement = Arrangement.spacedBy(Space.sm),
        ) {
            Text(
                "Evin dışından görmek için Mac'e ve telefona Tailscale kur, Mac'in Tailscale adresini buraya yaz (ör. 100.x.x.x ya da mac-adi).",
                style = NabizType.caption, color = c.textSecondary,
            )
            OutlinedTextField(
                value = remote, onValueChange = { remote = it; saved = false; probe = null },
                label = { Text("Uzak adres") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(Space.sm), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { vm.saveRemoteAddress(remote); saved = true }) { Text("Kaydet") }
                TextButton(onClick = { probe = "Deneniyor…"; vm.testRemote(remote) { ok -> probe = if (ok) "Bağlandı" else "Ulaşılamadı" } }) { Text("Bağlantıyı dene") }
            }
            val note = probe ?: if (saved) "Kaydedildi" else null
            if (note != null) Text(note, style = NabizType.caption, color = c.textSecondary)
            if (link.phase == LinkPhase.READY) Text("Bağlantı yolu: " + viaLabel(link.via), style = NabizType.caption, color = c.textTertiary)
        }
        SectionLabel("Bildirim tasarımı")
        NotifStylePicker(style, vm::setNotifStyle)
        SectionLabel("Bildirim")
        Group {
            Row2("Bildirim izni", "Mac kartı için bildirimler açık olmalı") { BackgroundAccess.openNotificationSettings(ctx) }
            RowDivider()
            Row2(if (BackgroundAccess.livePromotionOff(ctx)) "Canlı güncellemeler kapalı" else "Canlı güncellemeler", if (BackgroundAccess.livePromotionOff(ctx)) "Kapalı: açmak için dokun (durum çubuğu çipi ve dinamik ada)" else "Android 16: kartın durum çubuğunda canlı görünmesi") { BackgroundAccess.openLiveUpdateSettings(ctx) }
        }
        SectionLabel("Mac ile paylaş")
        Group {
            ShareRow("Bildirimler", "Telefon bildirimleri Mac'te görünür", share.bildirimler, share.bildirimler && !grants.bildirimErisimi) { toggleShare(ShareKey.BILDIRIMLER, it) }
            RowDivider()
            ShareRow("Aramaları yönet", "Yanıtla, reddet, ara. Gelen numara için arama kaydı izni de istenir", share.cagriYonetimi, share.cagriYonetimi && !grants.cagri) { toggleShare(ShareKey.CAGRI, it) }
            RowDivider()
            ShareRow("Kişiler", "Mac'te kişi listesi ve arayan adı", share.kisiler, share.kisiler && !grants.kisiler) { toggleShare(ShareKey.KISILER, it) }
            RowDivider()
            ShareRow("Arama geçmişi", "Mac'te son aramalar", share.aramaGecmisi, share.aramaGecmisi && !grants.aramaGecmisi) { toggleShare(ShareKey.ARAMA_GECMISI, it) }
        }
        if (deniedKey != null) {
            Text(
                "İzin verilmedi. Uygulama ayarlarından izin ver.", style = NabizType.caption, color = c.textSecondary,
                modifier = Modifier.pressable { BackgroundAccess.openAppDetails(ctx) }.padding(horizontal = Space.lg, vertical = Space.xs),
            )
        }
        Text("Veriler yalnız eşleşmiş Mac'e şifreli gider; Mac diske yazmaz.", style = NabizType.caption, color = c.textTertiary, modifier = Modifier.padding(horizontal = Space.lg))
        SectionLabel("Aktar")
        val aktarOn by vm.aktarEnabled.collectAsStateWithLifecycle()
        val aktarAuto by vm.aktarAuto.collectAsStateWithLifecycle()
        Group {
            ShareRow("Aktar'ı aç", "Mac ile dosya gönder ve al. Kapalıyken gelen teklifler reddedilir", aktarOn, false) { vm.setAktarEnabled(it) }
            RowDivider()
            ShareRow("Eşleşmiş Mac'ten otomatik kabul", "Teklif onay sormadan alınır. Fotoğraflar Pictures/Nabız, videolar Movies/Nabız, diğerleri Download/Nabız'a kaydedilir", aktarAuto, false) { vm.setAktarAuto(it) }
        }
        SectionLabel("Uyarılar")
        AlertGroup("Telefon", Subject.TELEFON, vm.alerts)
        AlertGroup("Mac", Subject.MAC, vm.alerts)
        Group { Row2("Deneme bildirimi gönder", "Uyarı kanalının çalıştığını gör") { vm.testAlert() } }
        SectionLabel("Arka planda çalışma")
        Group {
            Row2("Pil kısıtı", if (BackgroundAccess.batteryUnrestricted(ctx)) "Kısıtsız" else "Kısıtlı: kısıtsız yap") { BackgroundAccess.requestBattery(ctx) }
            RowDivider()
            Row2("Otomatik başlatma", "Xiaomi/HyperOS: Nabız için aç") { BackgroundAccess.openAutostart(ctx) }
        }
    }
    if (confirm) {
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Eşleşmeyi unut?") },
            text = { Text("Mac'te de eşleşmeyi silmen gerekir; sonra yeniden eşleştirirsin.") },
            confirmButton = { TextButton(onClick = { confirm = false; onUnpair() }) { Text("Unut") } },
            dismissButton = { TextButton(onClick = { confirm = false }) { Text("Vazgeç") } },
        )
    }
}

@Composable
private fun Group(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().background(MaterialTheme.nabiz.card, RoundedCornerShape(NabizShape.group))) { content() }
}

/** iOS inset ayirici: sol inset ile ince cizgi. */
@Composable
private fun RowDivider() {
    Box(Modifier.fillMaxWidth().padding(start = Space.lg).height(0.5.dp).background(MaterialTheme.nabiz.separator))
}

@Composable
private fun Row2(title: String, sub: String, enabled: Boolean = true, onClick: () -> Unit) {
    val c = MaterialTheme.nabiz
    Column(
        Modifier.fillMaxWidth().pressable(0.98f, enabled, onClick).padding(horizontal = Space.lg, vertical = Space.md),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(title, style = NabizType.rowTitle, color = if (enabled) c.text else c.textTertiary)
        Text(sub, style = NabizType.caption, color = c.textSecondary)
    }
}

/** Anahtarin calismasi icin gerekenler (arama yonetiminde arama kaydi yalniz gelen numara icin istenir). */
private fun requiredPermissions(key: ShareKey): Array<String> =
    if (key == ShareKey.CAGRI) runtimePermissions(key).filter { it != Manifest.permission.READ_CALL_LOG }.toTypedArray() else runtimePermissions(key)

private fun runtimePermissions(key: ShareKey): Array<String> = when (key) {
    ShareKey.CAGRI -> arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS, Manifest.permission.CALL_PHONE, Manifest.permission.READ_CALL_LOG)
    ShareKey.KISILER -> arrayOf(Manifest.permission.READ_CONTACTS)
    ShareKey.ARAMA_GECMISI -> arrayOf(Manifest.permission.READ_CALL_LOG)
    ShareKey.BILDIRIMLER -> emptyArray()
}

/** Anahtarli ayar satiri (uyari satirlariyla ayni yerlesim). `needsGrant`: anahtar acik ama sistem izni yok. */
@Composable
private fun ShareRow(title: String, sub: String, checked: Boolean, needsGrant: Boolean, onChange: (Boolean) -> Unit) {
    val c = MaterialTheme.nabiz
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Space.lg, vertical = Space.sm),
        horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = NabizType.rowTitle, color = c.text)
            Text(if (needsGrant) "İzin gerekli" else sub, style = NabizType.caption, color = c.textSecondary)
        }
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun AlertGroup(title: String, subject: Subject, store: AlertStore) {
    val c = MaterialTheme.nabiz
    SectionLabel(title)
    Group {
        AlertRule.entries.filter { subject in it.subjects }.forEachIndexed { idx, rule ->
            if (idx > 0) RowDivider()
            var cfg by remember { mutableStateOf(store.config(rule, subject)) }
            AlertRow(rule, subject, cfg) { n: RuleConfig ->
                cfg = n
                store.setOn(rule, subject, n.on); store.setEsik(rule, subject, n.esik); store.setSureDk(rule, subject, n.sureDk)
            }
        }
    }
}

@Composable
private fun AlertRow(rule: AlertRule, subject: Subject, cfg: RuleConfig, onChange: (RuleConfig) -> Unit) {
    val c = MaterialTheme.nabiz
    val esik = rule.esikRange(subject)
    val sure = rule.sureRange
    Column(Modifier.fillMaxWidth().padding(horizontal = Space.lg, vertical = Space.sm)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(rule.ad, style = NabizType.rowTitle, color = c.text)
                Text(rule.describe(subject, cfg), style = NabizType.caption, color = c.textSecondary)
            }
            Switch(checked = cfg.on, onCheckedChange = { onChange(cfg.copy(on = it)) })
        }
        if (cfg.on && esik != null) {
            Slider(
                value = cfg.esik.toFloat().coerceIn(esik.first.toFloat(), esik.last.toFloat()),
                onValueChange = { onChange(cfg.copy(esik = it.toInt())) },
                valueRange = esik.first.toFloat()..esik.last.toFloat(),
                steps = (esik.last - esik.first - 1).coerceAtLeast(0),
            )
        }
        if (cfg.on && sure != null) {
            if (rule == AlertRule.CPU_YUKSEK) Text("Süre", style = NabizType.caption, color = c.textTertiary)
            Slider(
                value = cfg.sureDk.toFloat().coerceIn(sure.first.toFloat(), sure.last.toFloat()),
                onValueChange = { onChange(cfg.copy(sureDk = it.toInt())) },
                valueRange = sure.first.toFloat()..sure.last.toFloat(),
                steps = (sure.last - sure.first - 1).coerceAtLeast(0),
            )
        }
    }
}
