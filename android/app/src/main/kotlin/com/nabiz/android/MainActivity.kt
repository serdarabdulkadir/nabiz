package com.nabiz.android

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import android.content.Intent
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.nabiz.android.alerts.AlertNotifier
import com.nabiz.android.service.NabizService
import com.nabiz.android.ui.NabizRoot
import com.nabiz.android.ui.theme.NabizTheme

class MainActivity : ComponentActivity() {
    private var requestedTab by mutableIntStateOf(-1)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        requestedTab = intent.getIntExtra(AlertNotifier.EXTRA_TAB, -1)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Servis hemen baslar (on plandaki activity'den izinli); izinler istenirken kanal arka planda aranir.
        NabizService.start(this)
        requestedTab = intent?.getIntExtra(AlertNotifier.EXTRA_TAB, -1) ?: -1
        setContent {
            val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
                // Bildirim izni sonradan verilirse kart gorunsun diye servis yeniden baslatilir (ayni ornek, tekrar bildirim yollar).
                NabizService.start(this@MainActivity)
            }
            LaunchedEffect(Unit) {
                if (Build.VERSION.SDK_INT >= 33) {
                    launcher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.NEARBY_WIFI_DEVICES))
                }
            }
            NabizTheme { NabizRoot(requestedTab = requestedTab, onTabHandled = { requestedTab = -1 }) }
        }
    }
}
