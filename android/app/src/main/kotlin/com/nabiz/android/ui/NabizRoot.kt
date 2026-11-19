package com.nabiz.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.Alignment
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nabiz.android.peer.LinkPhase
import com.nabiz.android.peer.LinkReason
import com.nabiz.android.ui.theme.NabizType
import com.nabiz.android.ui.theme.Space
import com.nabiz.android.ui.theme.nabiz
import kotlinx.coroutines.delay

@Composable
fun NabizRoot(requestedTab: Int = -1, onTabHandled: () -> Unit = {}, vm: MainViewModel = viewModel()) {
    val link by vm.link.collectAsStateWithLifecycle()
    val phone by vm.phone.collectAsStateWithLifecycle()
    val pinned by vm.pinned.collectAsStateWithLifecycle()
    val found by vm.found.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var settings by rememberSaveable { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle

    // Telefon olcumleri ekran gorunurken 2 sn'de bir.
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) { vm.refreshPhone(); delay(2000) }
        }
    }
    LaunchedEffect(requestedTab) {
        if (requestedTab in 0..1) { tab = requestedTab; settings = false; onTabHandled() }
    }
    BackHandler(enabled = settings) { settings = false }

    Box(Modifier.fillMaxSize().background(MaterialTheme.nabiz.bg).statusBarsPadding().navigationBarsPadding()) {
        AnimatedContent(
            targetState = settings,
            transitionSpec = {
                val push = targetState
                val sp = Motion.spring<IntOffset>()
                if (push) {
                    (slideInHorizontally(sp) { it } togetherWith (slideOutHorizontally(sp) { -it / 3 } + fadeOut(Motion.spring())))
                } else {
                    ((slideInHorizontally(sp) { -it / 3 } + fadeIn(Motion.spring())) togetherWith slideOutHorizontally(sp) { it })
                }.using(SizeTransform(clip = false)).apply { targetContentZIndex = if (push) 1f else 0f }
            },
            label = "settings",
        ) { inSettings ->
            Column(Modifier.fillMaxSize().background(MaterialTheme.nabiz.bg)) {
                if (inSettings) {
                    SettingsScreen(vm, pinnedName = pinned?.name, link = link, onUnpair = vm::unpair, onBack = { settings = false })
                } else {
                    Column(Modifier.padding(horizontal = Space.lg).padding(top = Space.md), verticalArrangement = Arrangement.spacedBy(Space.md)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text("Nabız", style = NabizType.pageTitle, color = MaterialTheme.nabiz.text)
                            Text(
                                "Ayarlar", style = NabizType.rowTitle, color = MaterialTheme.nabiz.textSecondary,
                                modifier = Modifier.pressable { settings = true }.padding(horizontal = Space.md, vertical = Space.sm),
                            )
                        }
                        Segmented(listOf("Telefon", "Mac" + (link.rttMs?.takeIf { link.phase == LinkPhase.READY }?.let { " · $it ms" } ?: "")), tab, { tab = it })
                    }
                    Column(
                        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(Space.lg),
                        verticalArrangement = Arrangement.spacedBy(Space.md),
                    ) {
                        AnimatedContent(
                            targetState = tab,
                            transitionSpec = {
                                val dir = if (targetState > initialState) 1 else -1
                                val sp = Motion.spring<IntOffset>()
                                ((slideInHorizontally(sp) { (it * 0.08f * dir).toInt() } + fadeIn(Motion.spring()))
                                    togetherWith (slideOutHorizontally(sp) { (-it * 0.08f * dir).toInt() } + fadeOut(Motion.spring())))
                                    .using(SizeTransform(clip = false))
                            },
                            label = "tab",
                        ) { t ->
                            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.md)) {
                                if (t == 0) PhoneTab(phone, vm.history) else MacTab(link, vm::sendCmd, vm.history, found, pinned?.id, vm::connectTo, vm::rescan)
                            }
                        }
                        Spacer(Modifier.height(Space.xl))
                    }
                }
            }
        }
    }

    if (link.phase == LinkPhase.AWAIT_SAS && link.sas != null) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text("Eşleşme kodu") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Space.sm)) {
                    Text("Mac'te de aynı kod görünüyorsa onayla.")
                    Text(link.sas!!, style = NabizType.code, color = MaterialTheme.nabiz.text)
                }
            },
            confirmButton = { TextButton(onClick = { vm.confirmSas(true) }) { Text("Onayla") } },
            dismissButton = { TextButton(onClick = { vm.confirmSas(false) }) { Text("Reddet") } },
        )
    }
}

fun reasonText(r: LinkReason, peerVersion: Int? = null): String? = when (r) {
    LinkReason.NONE -> null
    LinkReason.NOT_FOUND -> "Mac bulunamadı"
    LinkReason.LOST -> "Bağlantı koptu, yeniden deneniyor"
    LinkReason.REJECTED -> "Eşleşme reddedildi"
    LinkReason.KEY_CHANGED -> "Eşleşme anahtarı değişti: Ayarlar'dan eşleşmeyi unutup yeniden eşleştir"
    LinkReason.PROTOCOL -> "Protokol hatası"
    LinkReason.SLEEPING -> "Mac uykuda"
    LinkReason.VERSION -> "Mac'teki Nabız farklı sürümde (v${peerVersion ?: "?"}). İki uygulamayı da güncelleyin."
}
