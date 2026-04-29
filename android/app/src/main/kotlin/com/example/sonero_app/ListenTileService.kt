package com.example.sonero_app

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import id.flutter.flutter_background_service.BackgroundService

class ListenTileService : TileService() {

    override fun onTileAdded() {
        super.onTileAdded()
        val tile = qsTile
        tile.state = Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        
        val tile = qsTile
        tile.state = Tile.STATE_ACTIVE
        tile.updateTile()

        // Start the Flutter Background Service
        val intent = Intent(this, BackgroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        // Collapse the quick settings panel
        val closeIntent = Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
        sendBroadcast(closeIntent)

        // Reset tile state after a delay (simulating listening time)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            tile.state = Tile.STATE_INACTIVE
            tile.updateTile()
        }, 10000)
    }
}
