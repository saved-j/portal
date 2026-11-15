package com.follow.clashx

import android.app.Application
import android.content.Context
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalTelemetry
import com.follow.clashx.service.ServiceConfig

class FlClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }

    override fun onCreate() {
        super.onCreate()
        // The record has to exist before the first portal does, and it has to answer the
        // one question the log could never answer from logcat alone: which owner holds the
        // tunnel right now. The service's runtime is only visible from this module, so the
        // probe is wired here.
        PortalTelemetry.engineProbe = { ServiceController.engineListening }
        PortalTelemetry.portProbe = {
            val options = ServiceConfig.vpnOptions
            // The options' mixed port first, then the ports the two cores use when a
            // profile never named one: the probe answers with those that really listen.
            listOfNotNull(options?.port) + listOf(10810, 7890, 9090)
        }
        PortalTelemetry.start()
    }
}
