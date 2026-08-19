package com.tech.saveride

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Canal requis pour afficher les notifications FCM sur Android 8+ (API 26+).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "high_importance_channel",
                "Alertes SafeRide",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "SOS et notifications importantes"
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
