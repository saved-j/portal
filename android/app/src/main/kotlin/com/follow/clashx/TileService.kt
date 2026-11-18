package com.follow.clashx

import android.service.quicksettings.Tile
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalRuntimeState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class TileService : android.service.quicksettings.TileService() {
    private var scope: CoroutineScope? = null

    override fun onStartListening() {
        super.onStartListening()
        // The tile's own last state is not the truth: after a cold process start it still says
        // whatever was written before. The record is asked first, so the panel opens showing the
        // tunnel that actually exists.
        updateTileFromRecord()
        scope?.cancel()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { scope ->
            scope.launch {
                ServiceState.runState.collect(::updateTile)
            }
        }
    }

    // No Activity, ever.
    //
    // Upstream sends every tap through a transparent Activity only so that
    // `startActivityAndCollapse` closes the shade — AOSP drops any PendingIntent that is not an
    // activity, so nothing else can collapse the panel. The price of that trick is a window the
    // owner can see, and it is not a price worth paying: the shade stays open for one gesture
    // and the tile does its work in place, exactly like a system tile.
    //
    // The action goes through the portal coordinator, which is the same entry the app's own
    // button takes — one owner, one generation, one order. The tile is a second way to ask,
    // never a second mechanism.
    override fun onClick() {
        super.onClick()
        // The record decides, not the service machine's own last value: on a process started by
        // the tap itself that value is STOPPED even when the tunnel is up, and a tap would then
        // ask to start what is already running.
        val phase = PortalRuntimeState.current().phase
        val start = phase != "Active"
        GlobalState.log("PortalTile tile tap: phase=$phase -> ${if (start) "start" else "stop"}")
        GlobalState.launch {
            if (start) {
                PortalRuntimeCoordinator.openDesired()
            } else {
                PortalRuntimeCoordinator.close("quick-settings")
            }
        }
    }

    override fun onStopListening() {
        scope?.cancel()
        scope = null
        super.onStopListening()
    }

    /// The record's phase, mapped onto the tile's three states.
    private fun updateTileFromRecord() {
        val phase = PortalRuntimeState.current().phase
        // Never UNAVAILABLE: SystemUI drops taps on an unavailable tile, and a tile that is
        // busy for half a second must still accept the next tap. Active is the only state the
        // owner reads as "on"; everything else reads as "off" and stays clickable.
        setTileState(if (phase == "Active") Tile.STATE_ACTIVE else Tile.STATE_INACTIVE)
    }

    private fun setTileState(state: Int) {
        qsTile?.apply {
            this.state = state
            updateTile()
        }
    }

    private fun updateTile(runState: RunState) {
        qsTile?.apply {
            state = when (runState) {
                RunState.STARTED -> Tile.STATE_ACTIVE
                else -> Tile.STATE_INACTIVE
            }
            updateTile()
        }
    }

}
