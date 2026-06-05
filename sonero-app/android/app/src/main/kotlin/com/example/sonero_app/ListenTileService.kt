package com.example.sonero_app

import android.app.ActivityManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService

class ListenTileService : TileService(), SharedPreferences.OnSharedPreferenceChangeListener {
    private val TAG = "ListenTileService"
    private var sharedPreferences: SharedPreferences? = null

    override fun onTileAdded() {
        super.onTileAdded()
        Log.d(TAG, "onTileAdded called")
        updateTileState()
    }

    override fun onStartListening() {
        super.onStartListening()
        Log.d(TAG, "onStartListening called")
        sharedPreferences = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        sharedPreferences?.registerOnSharedPreferenceChangeListener(this)
        updateTileState()
    }

    override fun onStopListening() {
        super.onStopListening()
        Log.d(TAG, "onStopListening called")
        sharedPreferences?.unregisterOnSharedPreferenceChangeListener(this)
        sharedPreferences = null
    }

    override fun onSharedPreferenceChanged(sharedPreferences: SharedPreferences?, key: String?) {
        if (key == "flutter.is_listening") {
            Log.d(TAG, "flutter.is_listening preference changed, updating tile state")
            updateTileState()
        }
    }

    override fun onClick() {
        super.onClick()
        Log.d(TAG, "onClick called")
        
        val tile = qsTile ?: run {
            Log.e(TAG, "qsTile is null in onClick")
            return
        }

        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isListening = prefs.getBoolean("flutter.is_listening", false)
        Log.d(TAG, "Current listening status from pref: $isListening")

        if (!isListening) {
            // Set immediately to true for instant visual feedback
            prefs.edit().putBoolean("flutter.is_listening", true).apply()
            updateTileState()

            val running = isServiceRunning()
            Log.d(TAG, "Service running status: $running")

            if (running) {
                Log.d(TAG, "Service is running, invoking listen_now action via pipe")
                try {
                    val json = org.json.JSONObject()
                    json.put("method", "listen_now")
                    json.put("args", org.json.JSONObject())
                    id.flutter.flutter_background_service.FlutterBackgroundServicePlugin.servicePipe.invoke(json)
                    Log.d(TAG, "Action invoked successfully")
                } catch (e: java.lang.Exception) {
                    Log.e(TAG, "Failed to invoke listen_now action: ${e.message}", e)
                    prefs.edit().putBoolean("flutter.is_listening", false).apply()
                    updateTileState()
                }
            } else {
                Log.d(TAG, "Service is not running, writing preference flag started_from_tile=true")
                prefs.edit().putBoolean("flutter.started_from_tile", true).apply()

                // Open the app to bring it to the foreground, which starts the background service safely.
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, flags)

                    Log.d(TAG, "Starting MainActivity from TileService (SDK_INT: ${Build.VERSION.SDK_INT})")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startActivityAndCollapse(pendingIntent)
                    } else {
                        @Suppress("DEPRECATION")
                        startActivityAndCollapse(launchIntent)
                    }
                } else {
                    Log.e(TAG, "Launch intent is null for package: $packageName")
                    prefs.edit().putBoolean("flutter.is_listening", false).apply()
                    updateTileState()
                }
            }
        }

        // Collapse the quick settings panel safely (only on Android versions older than Android 12 / S)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            @Suppress("DEPRECATION")
            val closeIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
            sendBroadcast(closeIntent)
        }
    }

    private fun isServiceRunning(): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        @Suppress("DEPRECATION")
        for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
            if ("id.flutter.flutter_background_service.BackgroundService" == service.service.className) {
                return true
            }
        }
        return false
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val prefs = sharedPreferences ?: getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isListening = prefs.getBoolean("flutter.is_listening", false)
        Log.d(TAG, "updateTileState called, isListening: $isListening")
        
        tile.state = if (isListening) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (isListening) "Escuchando..." else "Toca para escuchar"
        }
        tile.updateTile()
    }
}
