package com.follow.clashx

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.intent
import com.follow.clashx.core.Core
import com.follow.clashx.service.ManagedService
import com.follow.clashx.service.NetworkObserver
import com.follow.clashx.service.ProxyService
import com.follow.clashx.service.ServiceConfig
import com.follow.clashx.service.VpnService
import com.follow.clashx.service.models.VpnOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume

object ServiceController {
    private val lock = Mutex()
    private var binding: ManagedServiceBinding? = null

    @Volatile
    internal var runtime: ServiceRuntime? = null
        private set

    /// The tunnel is read by the Xray child, so the Core is neither started nor stopped here.
    @Volatile
    private var xrayTunActive = false

    private fun clearBinding() {
        binding?.unbind()
        binding = null
    }

    // The Core listens exactly while a run exists, so every path that ends one closes it.
    private fun release() {
        clearBinding()
        runtime = null
        // Also in the simple portal: the Core was not started *here*, but it may have been
        // started before this run — Dart's `startListener`, or a network run whose tunnel the
        // child then took — and a listener left behind is a second reader of the interface
        // that carries the run. `StopListener` in Go is idempotent (it answers at once when
        // nothing runs), so the call is unconditional.
        Core.stopListener()
        xrayTunActive = false
    }

    fun invokeMethod(data: String, callback: (ByteArray) -> Unit): Result<Unit> = runCatching {
        Core.invokeMethod(data) { result ->
            callback(result ?: ByteArray(0))
        }
    }

    suspend fun quickSetup(
        initParams: String,
        setupParams: String,
    ): Result<String> = runCatching {
        NetworkObserver.start()
        suspendCancellableCoroutine { continuation ->
            Core.quickSetup(initParams, setupParams) { result ->
                continuation.resume(result.orEmpty())
            }
        }
    }

    fun setEventListener(callback: ((ByteArray) -> Unit)?): Result<Unit> = runCatching {
        Core.updateEventListener(callback)
    }

    suspend fun start(options: VpnOptions): Boolean = lock.withLock {
        ServiceConfig.updateVpnOptions(options)
        // The simple portal's tunnel belongs to the child alone, so anything of the engine
        // that is still listening goes before the service publishes the descriptor: Dart's
        // `startListener` opens the engine and *then* asks for the service, which is how the
        // engine kept reading the interface the child had been handed. The Go call is
        // idempotent — with nothing running it answers at once — so it is asked every time.
        if (options.xrayTun) {
            Core.stopListener()
        }
        val nextIntent = if (options.enable) {
            VpnService::class.intent
        } else {
            ProxyService::class.intent
        }

        if (binding?.component != nextIntent.component) {
            if (binding != null) {
                tearDownServices()
            }
            lateinit var nextBinding: ManagedServiceBinding
            nextBinding = ManagedServiceBinding(nextIntent) { message ->
                handleServiceDisconnected(nextBinding, message)
            }
            binding = nextBinding
            nextBinding.bind().onFailure { error ->
                GlobalState.log("Unable to bind background service: $error")
                release()
                return@withLock false
            }
        }

        val currentBinding = binding ?: return@withLock false
        val result = currentBinding.useService { service -> service.start() }
        if (result.isFailure) {
            GlobalState.log("Unable to start background service: ${result.exceptionOrNull()}")
            currentBinding.stopIfConnected()
                .onFailure { error ->
                    GlobalState.log("Unable to clean up failed background service start: $error")
                }
            release()
            return@withLock false
        }

        // The simple portal's tunnel is read by the Xray child: the engine is neither started
        // nor configured here, and its listener state is left exactly as it was.
        xrayTunActive = options.xrayTun
        if (!options.xrayTun) {
            Core.startListener()
        }
        runtime = ServiceRuntime(
            vpn = options.enable,
            startedAtMillis = runtime?.startedAtMillis ?: System.currentTimeMillis(),
        )
        true
    }

    suspend fun stop() = lock.withLock {
        tearDownServices()
        release()
    }

    private suspend fun tearDownServices() {
        binding?.useService { service -> service.stop() }
            ?.onFailure { error ->
                GlobalState.log("Unable to stop background service: $error")
            }
        clearBinding()
        stopServices()
    }

    // A service the system started itself — always-on VPN, or the sticky restart
    // after the process was killed — outlives every binding this process holds, so
    // unbinding alone leaves the tunnel up while the app reports it stopped.
    private fun stopServices() {
        listOf(VpnService::class.intent, ProxyService::class.intent).forEach { intent ->
            runCatching { GlobalState.application.stopService(intent) }
                .onFailure { error ->
                    GlobalState.log("Unable to stop ${intent.component?.className}: $error")
                }
        }
    }

    private fun handleServiceDisconnected(
        disconnectedBinding: ManagedServiceBinding,
        message: String,
    ) {
        val token = ServiceState.captureRequestToken()
        GlobalState.launch {
            val wasCurrent = lock.withLock {
                if (binding !== disconnectedBinding) {
                    return@withLock false
                }
                GlobalState.log("Background service disconnected: $message")
                release()
                true
            }
            if (wasCurrent) {
                ServiceState.handleServiceLost(token)
            }
        }
    }
}

private class ManagedServiceBinding(
    private val intent: Intent,
    private val onDisconnected: (String) -> Unit,
) : ServiceConnection {
    val component: ComponentName?
        get() = intent.component

    private val serviceState = MutableStateFlow<Result<ManagedService>?>(null)

    @Volatile
    private var isBound = false

    suspend fun bind(): Result<Unit> = runCatching {
        withContext(Dispatchers.Main.immediate) {
            serviceState.value = null
            isBound = GlobalState.application.bindService(
                intent,
                this@ManagedServiceBinding,
                Context.BIND_AUTO_CREATE,
            )
            check(isBound) { "bindService() failed" }
        }
    }

    suspend fun <R> useService(
        connectionTimeoutMillis: Long = 5_000,
        block: suspend (ManagedService) -> R,
    ): Result<R> = runCatching {
        val service = withTimeout(connectionTimeoutMillis) {
            serviceState.filterNotNull().first().getOrThrow()
        }
        withContext(Dispatchers.Default) {
            block(service)
        }
    }

    suspend fun stopIfConnected(): Result<Unit> = runCatching {
        val service = serviceState.value?.getOrNull() ?: return@runCatching
        withContext(Dispatchers.Default) {
            service.stop()
        }
    }

    fun unbind() {
        serviceState.value = null
        if (!isBound) return
        isBound = false
        Handler(Looper.getMainLooper()).post {
            runCatching {
                GlobalState.application.unbindService(this)
            }.onFailure { error ->
                GlobalState.log("Unable to unbind background service: $error")
            }
        }
    }

    override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
        runCatching {
            when (binder) {
                is VpnService.LocalBinder -> binder.service
                is ProxyService.LocalBinder -> binder.service
                null -> error("Binder is empty")
                else -> error("Unsupported service binder: ${binder.javaClass.name}")
            }
        }.onSuccess { service ->
            serviceState.value = Result.success(service)
        }.onFailure { error ->
            disconnect(error.message.orEmpty())
        }
    }

    override fun onServiceDisconnected(name: ComponentName?) {
        disconnect("Service disconnected")
    }

    override fun onBindingDied(name: ComponentName?) {
        disconnect("Service binding died")
    }

    override fun onNullBinding(name: ComponentName?) {
        disconnect("Service returned an empty binder")
    }

    private fun disconnect(message: String) {
        serviceState.value = Result.failure(IllegalStateException(message))
        onDisconnected(message)
    }
}
