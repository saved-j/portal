package com.follow.clashx.plugins

import com.follow.clashx.PortalOutcome
import com.follow.clashx.PortalRuntimeCoordinator
import com.follow.clashx.common.Components
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalOwner
import com.follow.clashx.common.PortalRuntimeState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * The channel the app's own Dart drives the portal with.
 *
 * One entry, one answer: every call here goes through [PortalRuntimeCoordinator], which owns
 * the mutex, the generation and the tunnel's owner. A call answers when the transaction is
 * over — `ok` only when the owner acknowledged the tunnel — so a caller no longer has to
 * guess from a fire-and-forget `true` whether the tunnel it asked for exists.
 *
 * `prepareChildConfig` is the reverse direction: an entry that arrived without a document
 * (Quick Settings, Always-on) asks Dart for one inside the transaction, because the profile
 * the document is built from lives there.
 */
class PortalRuntimePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        // Dart builds the document; the coordinator asks for it while it holds the lock.
        PortalRuntimeCoordinator.provideChildConfig {
            requestChildConfig()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        PortalRuntimeCoordinator.provideChildConfig(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                val owner = PortalOwner.of(call.argument<String>("owner"))
                if (owner == null) {
                    result.success(
                        PortalOutcome(ok = false, reason = "unknown owner").toMap(),
                    )
                    return
                }
                val config = call.argument<String>("config")
                GlobalState.launch { result.success(PortalRuntimeCoordinator.open(owner, config).toMap()) }
            }

            "close" -> GlobalState.launch {
                result.success(PortalRuntimeCoordinator.close(call.argument<String>("reason") ?: "app").toMap())
            }

            "restart" -> GlobalState.launch {
                result.success(PortalRuntimeCoordinator.restart(call.argument<String>("config")).toMap())
            }

            "startChild" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrBlank()) {
                    result.success(
                        PortalOutcome(ok = false, reason = "empty config").toMap(),
                    )
                    return
                }
                GlobalState.launch {
                    result.success(PortalRuntimeCoordinator.startChild(config).toMap())
                }
            }

            "status" -> result.success(PortalRuntimeCoordinator.status())

            else -> result.notImplemented()
        }
    }

    /// Asks Dart for the document of the node the portal currently picks.
    private suspend fun requestChildConfig(): String? =
        suspendCancellableCoroutine { continuation ->
            val main = android.os.Handler(android.os.Looper.getMainLooper())
            main.post {
                runCatching {
                    channel.invokeMethod(
                        "prepareChildConfig",
                        null,
                        object : MethodChannel.Result {
                            override fun success(answer: Any?) {
                                if (continuation.isActive) {
                                    continuation.resume((answer as? String)?.takeIf { it.isNotBlank() })
                                }
                            }

                            override fun error(code: String, message: String?, details: Any?) {
                                GlobalState.log("prepareChildConfig failed: $code $message")
                                if (continuation.isActive) continuation.resume(null)
                            }

                            override fun notImplemented() {
                                if (continuation.isActive) continuation.resume(null)
                            }
                        },
                    )
                }.onFailure { error ->
                    GlobalState.log("prepareChildConfig unavailable: $error")
                    if (continuation.isActive) continuation.resume(null)
                }
            }
        }

    private companion object {
        val CHANNEL = "${Components.PACKAGE_NAME}/portal"
    }
}
