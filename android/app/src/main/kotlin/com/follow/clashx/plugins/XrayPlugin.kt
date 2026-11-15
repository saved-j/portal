package com.follow.clashx.plugins

import android.content.Context
import android.util.Log
import com.follow.clashx.common.Components
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.zip.ZipFile

/**
 * Runs the bundled Xray next to the in-process engine.
 *
 * The engine keeps the TUN and the rule engine; Xray owns the real node and is reached
 * through a socks5 outbound the host declares in the engine's config. That split is not a
 * preference: a child process cannot inherit the tun descriptor, and its sockets cannot be
 * protected by the VpnService, so letting the child own the tunnel would loop its own
 * traffic straight back into the tunnel.
 *
 * Ported from the PortalVPN legacy client, which ran a bridge the same way and answered the
 * same health check.
 */
class XrayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var process: Process? = null
    @Volatile private var lastLine: String = ""

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "start" -> {
                val config = call.argument<String>("config")
                val port = call.argument<Int>("port") ?: DEFAULT_PORT
                if (config.isNullOrBlank()) {
                    result.success(mapOf("ok" to false, "message" to "empty config"))
                    return
                }
                executor.execute {
                    val outcome = start(config, port)
                    channel.invokeMethodOnMainThread("state", status())
                    result.success(outcome)
                }
            }
            "stop" -> {
                executor.execute {
                    stop()
                    channel.invokeMethodOnMainThread("state", status())
                    result.success(mapOf("ok" to true, "message" to "stopped"))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> = mapOf(
        "running" to (process?.isAlive == true),
        "lastLine" to lastLine,
    )

    private fun start(config: String, port: Int): Map<String, Any> {
        stop()
        val binary = binary() ?: return failure("libxray.so is missing from the APK")
        val configFile = File(appContext.filesDir, "xray.json")
        configFile.writeText(config, Charsets.UTF_8)

        return try {
            val builder = ProcessBuilder(binary.absolutePath, "run", "-c", configFile.absolutePath)
                .directory(appContext.filesDir)
                .redirectErrorStream(true)
            val started = builder.start()
            process = started
            drain(started)

            val deadline = System.currentTimeMillis() + READY_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                if (!started.isAlive) {
                    val code = runCatching { started.exitValue() }.getOrDefault(-1)
                    stop()
                    return failure("xray exited with $code: $lastLine")
                }
                if (reachable(port)) {
                    Log.i(TAG, "xray is listening on 127.0.0.1:$port")
                    return mapOf("ok" to true, "message" to "listening on $port")
                }
                Thread.sleep(200)
            }
            stop()
            failure("xray did not open 127.0.0.1:$port within ${READY_TIMEOUT_MS}ms: $lastLine")
        } catch (e: Exception) {
            Log.e(TAG, "unable to start xray", e)
            stop()
            failure(e.message ?: "unable to start xray")
        }
    }

    private fun stop() {
        val current = process ?: return
        process = null
        runCatching {
            current.destroy()
            if (!current.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)) {
                current.destroyForcibly()
                current.waitFor(2, java.util.concurrent.TimeUnit.SECONDS)
            }
        }.onFailure { Log.w(TAG, "stop: ${it.message}") }
    }

    /**
     * Only the APK's native library directory is executable by an app targeting API 29+;
     * a copy in filesDir fails with EACCES however its mode bits read.
     */
    private fun binary(): File? {
        val native = File(appContext.applicationInfo.nativeLibraryDir, LIB_NAME)
        if (native.exists()) return native
        // A build whose native sources were not extracted still carries the file in the zip.
        return runCatching {
            ZipFile(appContext.applicationInfo.sourceDir).use { zip ->
                val entry = zip.getEntry("lib/arm64-v8a/$LIB_NAME")
                    ?: zip.getEntry("lib/armeabi-v7a/$LIB_NAME")
                    ?: zip.getEntry("lib/x86_64/$LIB_NAME")
                    ?: return@use null
                val out = File(appContext.filesDir, LIB_NAME)
                zip.getInputStream(entry).use { input ->
                    out.outputStream().use { output -> input.copyTo(output) }
                }
                out.setExecutable(true)
                out
            }
        }.getOrNull()
    }

    private fun drain(started: Process) {
        executor.execute {
            runCatching {
                started.inputStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                    for (line in lines) {
                        lastLine = line
                        if (line.contains("error", true) || line.contains("fatal", true)) {
                            Log.e(TAG, line)
                        } else {
                            Log.i(TAG, line)
                        }
                    }
                }
            }.onFailure { Log.w(TAG, "output stream closed: ${it.message}") }
        }
    }

    private fun reachable(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 400) }
        true
    }.getOrDefault(false)

    private fun failure(message: String): Map<String, Any> =
        mapOf("ok" to false, "message" to message)

    private fun MethodChannel.invokeMethodOnMainThread(method: String, arguments: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            invokeMethod(method, arguments)
        }
    }

    companion object {
        private const val TAG = "XrayCore"
        private const val LIB_NAME = "libxray.so"
        private const val READY_TIMEOUT_MS = 10_000L
        const val DEFAULT_PORT = 10808
        val CHANNEL = "${Components.PACKAGE_NAME}/xray"
    }
}
