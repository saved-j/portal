package com.follow.clashx.service.modules

import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.Service
import android.app.Service.STOP_FOREGROUND_REMOVE
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import com.follow.clashx.common.Components
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.BroadcastAction
import com.follow.clashx.common.QuickAction
import com.follow.clashx.common.ensureNotificationChannel
import com.follow.clashx.common.quickIntent
import com.follow.clashx.common.receiveBroadcastFlow
import com.follow.clashx.common.startForeground
import com.follow.clashx.common.toPendingBroadcast
import com.follow.clashx.common.toPendingIntent
import com.follow.clashx.service.R
import com.follow.clashx.service.ServiceConfig
import com.follow.clashx.service.models.NotificationParams
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

internal class NotificationModule(
    private val service: Service,
    private val scope: CoroutineScope,
) : ServiceModule {
    override fun start() {
        service.ensureNotificationChannel()
        update(ServiceConfig.notificationParams.value)
        scope.launch {
            // Some ROMs, vivo's among them, drop updates posted behind the
            // keyguard, so unlocking posts once more. SystemUI, an app, sends
            // USER_PRESENT, which a receiver that is not exported never gets;
            // the action is protected.
            val unlocked = service.receiveBroadcastFlow(exported = true) {
                addAction(Intent.ACTION_USER_PRESENT)
            }.map { }.onStart { emit(Unit) }
            combine(unlocked, ServiceConfig.notificationParams) { _, params -> params }
                .collect(::update)
        }
    }

    private val notificationBuilder: NotificationCompat.Builder by lazy {
        val intent = Intent().setComponent(Components.mainActivity)

        NotificationCompat.Builder(
            service,
            GlobalState.NOTIFICATION_CHANNEL,
        ).apply {
            setSmallIcon(R.drawable.ic_service)
            setContentIntent(intent.toPendingIntent)
            setPriority(NotificationCompat.PRIORITY_LOW)
            setCategory(NotificationCompat.CATEGORY_SERVICE)
            setOngoing(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
            }
            setShowWhen(true)
            setOnlyAlertOnce(true)
        }
    }

    private val stopIntent by lazy { QuickAction.STOP.quickIntent.toPendingIntent }

    // The test button is a broadcast, not an activity, so tapping it never brings the app
    // to the foreground — the ping just runs in the service.
    private val pingIntent by lazy { BroadcastAction.PING.toPendingBroadcast }

    // In the simple portal the same slot cycles the xray node, also without the app.
    private val nextIntent by lazy { BroadcastAction.NEXT_SERVER.toPendingBroadcast }

    private fun update(params: NotificationParams) {
        // The expanded shade is a custom view because the standard action row always stacks its
        // buttons together, and the owner wants Stop on the left and the bolt on the right.
        val views = RemoteViews(service.packageName, R.layout.notification_portal).apply {
            setTextViewText(R.id.notif_title, params.title)
            setTextViewText(R.id.notif_info, params.detail)
            setViewVisibility(
                R.id.notif_info,
                if (params.detail.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            setTextViewText(R.id.notif_server, params.server)
            setTextViewText(R.id.notif_latency, params.latency)
            setViewVisibility(
                R.id.notif_latency,
                if (params.latency.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            setTextViewText(R.id.notif_stats, params.stats)
            setViewVisibility(
                R.id.notif_stats,
                if (params.stats.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            setTextViewText(R.id.notif_stop, params.stopText)
            setTextColor(R.id.notif_stop, STOP_COLOR)
            setOnClickPendingIntent(R.id.notif_stop, stopIntent)
            setViewVisibility(
                R.id.notif_stop,
                if (params.showStopAction) View.VISIBLE else View.GONE,
            )
            setTextViewText(R.id.notif_ping, params.pingText)
            setTextColor(R.id.notif_ping, PING_COLOR)
            setOnClickPendingIntent(
                R.id.notif_ping,
                if (params.nextAction) nextIntent else pingIntent,
            )
            setViewVisibility(
                R.id.notif_ping,
                if (params.showPing) View.VISIBLE else View.GONE,
            )
        }
        service.startForeground(
            with(notificationBuilder) {
                setContentTitle(params.title)
                if (params.server.isNotEmpty()) {
                    setContentText(params.server)
                }
                setCustomBigContentView(views)
                clearActions()
                build()
            },
        )
    }

    @Suppress("DEPRECATION")
    override fun stop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            service.stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            service.stopForeground(true)
        }
    }

    private companion object {
        val STOP_COLOR = 0xFFFF6E6E.toInt()
        val PING_COLOR = 0xFFFFC107.toInt()
    }
}
