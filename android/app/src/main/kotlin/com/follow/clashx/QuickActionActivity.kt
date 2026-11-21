package com.follow.clashx

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.content.pm.ShortcutManagerCompat
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.QuickAction
import com.follow.clashx.common.action
import com.follow.clashx.common.shortcutId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class QuickActionActivity : Activity() {
    private var hold: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12 passes touches through another app's window only if it is fully
        // transparent. `alpha = 0f` makes the window transparent but not *fully* one in the
        // system's eyes, and on a translucent theme that is enough for the system to run the
        // activity's open/close animation — which is the flash Mark saw when tapping the tile.
        // A 1px transparent window, no dim and no transition is the combination that the system
        // treats as "not really a window".
        window.attributes = window.attributes.apply {
            width = 1
            height = 1
            gravity = android.view.Gravity.TOP or android.view.Gravity.START
            alpha = 0f
            dimAmount = 0f
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // No enter/exit animation at all: nothing to see, nothing to animate.
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        window.setDimAmount(0f)
        // Kept on purpose: the touch that opened this window must not reach the app behind it.
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
        // A recreated instance gets the same intent again; a second dispatch turns a TOGGLE back.
        if (savedInstanceState == null) {
            handle(intent)
        }
        holdUntilStarted()
    }

    // A caller that repeats an action before this instance is gone reaches it here, not onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onDestroy() {
        hold?.cancel()
        super.onDestroy()
    }

    private fun handle(intent: Intent) {
        val action = QuickAction.entries.firstOrNull { it.action == intent.action } ?: return
        ShortcutManagerCompat.reportShortcutUsed(this, action.shortcutId)
        mainThreadActionsInFlight++
        GlobalState.launch {
            try {
                // The same entry the app and Quick Settings take: the coordinator decides
                // the owner, the order and the generation, and this holds until it answers.
                when (action) {
                    QuickAction.START -> PortalRuntimeCoordinator.openDesired()
                    QuickAction.STOP -> PortalRuntimeCoordinator.close("quick-action")
                    QuickAction.TOGGLE -> PortalRuntimeCoordinator.toggle()
                    QuickAction.PING -> PortalRuntimeCoordinator.ping()
                }
            } finally {
                withContext(Dispatchers.Main) { mainThreadActionsInFlight-- }
            }
        }
    }

    // A service goes foreground only while its app is or just was visible; Core setup outlasts it.
    private fun holdUntilStarted() {
        hold?.cancel()
        hold = GlobalState.launch(Dispatchers.Main) {
            while (mainThreadActionsInFlight > 0 || isStartPending()) {
                delay(HOLD_POLL_MILLIS)
            }
            finish()
        }
    }

    private fun isStartPending(): Boolean =
        ServiceState.isRunRequested && ServiceState.runState.value != RunState.STARTED

    private companion object {
        const val HOLD_POLL_MILLIS = 100L

        var mainThreadActionsInFlight = 0
    }
}
