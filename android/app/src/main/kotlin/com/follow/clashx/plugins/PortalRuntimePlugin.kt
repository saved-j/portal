package com.follow.clashx.plugins

import com.follow.clashx.PortalOutcome
import com.follow.clashx.PortalRuntimeCoordinator
import com.follow.clashx.common.Components
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalMeasureBridge
import com.follow.clashx.common.PortalOwner
import com.follow.clashx.common.PortalRuntimeState
import com.follow.clashx.common.PortalTelemetry
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

            // The measurement core: started for a sweep and stopped right after, never a
            // portal. The core itself belongs to the xray plugin; the bridge is how this
            // channel reaches it.
            "measureStart" -> {
                val config = call.argument<String>("config")
                val tags = call.argument<String>("tags")
                val url = call.argument<String>("url") ?: ""
                val timeoutMs = (call.argument<Number>("timeoutMs") ?: 8000).toInt()
                val bridge = PortalMeasureBridge.start
                if (config.isNullOrBlank() || tags.isNullOrBlank() || bridge == null) {
                    result.success(
                        mapOf(
                            "ok" to false,
                            "message" to if (bridge == null) "no child on this platform" else "empty config",
                        ),
                    )
                    return
                }
                GlobalState.launch { result.success(bridge(config, tags, url, timeoutMs)) }
            }

            "measureStop" -> {
                val bridge = PortalMeasureBridge.stop
                GlobalState.launch {
                    result.success(mapOf("ok" to (bridge?.invoke() ?: false)))
                }
            }

            "status" -> result.success(PortalRuntimeCoordinator.status())

            // The switch's own clock: the tap starts it here, and the record's hook writes
            // `phase=active` when the new owner acknowledges; the screen writes `phase=list`
            // when it has rows to draw. Both lines land in portal-transitions.log.
            "switchStart" -> {
                PortalTelemetry.noteSwitchStart(call.argument<String>("to") ?: "")
                result.success(null)
            }

            "switchTiming" -> {
                PortalTelemetry.noteSwitchTiming(
                    phase = call.argument<String>("phase") ?: "list",
                    durationMs = (call.argument<Number>("durationMs") ?: 0).toLong(),
                    detail = call.argument<String>("detail") ?: "",
                )
                result.success(null)
            }

            // A delay test that raised a core: which one, and how long the raise took.
            "testNote" -> {
                PortalTelemetry.noteTest(
                    mode = call.argument<String>("mode") ?: "",
                    raised = call.argument<String>("raised") ?: "",
                    durationMs = (call.argument<Number>("durationMs") ?: 0).toLong(),
                    stoppedAfter = call.argument<Boolean>("stoppedAfter") ?: false,
                    detail = call.argument<String>("detail") ?: "",
                )
                result.success(null)
            }

            // One attempt at a mode's own feed. The app counts these; the record writes the
            // line, so the count can be read off the phone instead of off a screenshot.
            "availabilityNote" -> {
                PortalTelemetry.noteAvailability(
                    feed = call.argument<String>("feed") ?: "",
                    mode = call.argument<String>("mode") ?: "",
                    attempts = (call.argument<Number>("attempts") ?: 0).toInt(),
                    limit = (call.argument<Number>("limit") ?: 0).toInt(),
                    state = call.argument<String>("state") ?: "",
                    reason = call.argument<String>("reason") ?: "",
                )
                result.success(null)
            }

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
