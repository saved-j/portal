package com.follow.clashx.plugins

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.Log
import com.follow.clashx.common.Components
import com.follow.clashx.common.XrayChildControl
import com.follow.clashx.common.XrayTun
import com.follow.clashx.common.XrayTunHolder
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import java.util.zip.ZipFile

/**
 * Runs the bundled Xray on the simple portal's tunnel.
 *
 * The VpnService establishes the tun — no other component can — and this plugin hands that
 * very descriptor to the child through its `tun` inbound. There is no engine in front of it
 * and no socks bridge behind it: the system routes packets into the tun, the child reads
 * them, and the node it dials is the one the owner picked.
 *
 * The descriptor crosses exec by inheritance, so the child reads the same number: close-on-
 * exec is cleared on it and the number is stated in `xray.tun.fd`. The start is only a
 * success once the child has acknowledged the tunnel in its own output; a child that exits,
 * or one that never takes the descriptor, fails the start with its last line instead of
 * falling back to a bridge it no longer has.
 *
 * Protecting the child's transport: `VpnService.protect` takes a socket from the calling
 * process, and the child's sockets are created after exec by Go, so it cannot be used here.
 * What it can do is bind every outbound to the interface the tunnel rides on, stated as
 * `autoOutboundsInterface`; the service resolves that interface and refuses to hand over a
 * tunnel without one.
 */
class XrayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var process: Process? = null
    @Volatile private var lastLine: String = ""
    @Volatile private var acknowledged = false

    /// The tunnel this plugin was handed, kept for the life of the VPN.
    ///
    /// The service publishes it once, when it establishes the interface; the child is
    /// restarted on every pick, and each restart reads the same descriptor. Taking it once
    /// and keeping it is what lets a tap replace the process without replacing the tunnel.
    @Volatile private var cachedTun: XrayTun? = null

    /// Every command takes a number; only the newest one may touch the process.
    ///
    /// A stop has to invalidate a start that is already waiting *and* one still queued
    /// behind it on the executor, which a shared boolean cannot do: the queued start would
    /// clear it and go on to spawn a child nobody asked for any more. The number only ever
    /// grows, so an older command compares false wherever it wakes up.
    private val operation = AtomicLong(0)

    private fun nextOperation(): Long = operation.incrementAndGet()

    private fun isCurrent(token: Long): Boolean = operation.get() == token

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        // The service takes the child down with the tunnel, so a revoked VPN cannot leave a
        // process reading a descriptor nobody answers for. Taking a number first also kills
        // any start the service's teardown interrupted before it could spawn.
        XrayChildControl.stop = {
            nextOperation()
            // The service is closing the descriptor it owns: the tunnel in hand is gone with
            // it, and so is whatever is reading it. Called on the service's own thread, so
            // kill and return — the wait belongs on the executor, not on a stopping service.
            cachedTun = null
            killNow()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        XrayChildControl.stop = null
        nextOperation()
        stop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            "start" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrBlank()) {
                    result.success(failure("empty config"))
                    return
                }
                // Numbered here, on the platform thread, so start and stop are ordered by
                // arrival: the newest command is the one that owns the process.
                val token = nextOperation()
                executor.execute {
                    if (!isCurrent(token)) {
                        result.success(cancelled())
                        return@execute
                    }
                    val outcome = start(token, config)
                    channel.invokeMethodOnMainThread("state", status())
                    result.success(outcome)
                }
            }
            "stop" -> {
                // Kill the child from this thread, not from the queue: a start that is still
                // waiting for its acknowledgement holds the only executor slot, and a stop
                // queued behind it would arrive after the timeout it exists to cut short.
                // Taking a number first invalidates every start, running or queued.
                val token = nextOperation()
                val killed = killNow()
                executor.execute {
                    // The process being reaped belongs to an older command whatever arrived
                    // since, so it is always reaped; only the state report follows the number.
                    killed?.let { reap(it) }
                    if (isCurrent(token)) {
                        channel.invokeMethodOnMainThread("state", status())
                    }
                    result.success(mapOf("ok" to true, "message" to "stopped"))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> = mapOf(
        "running" to (process?.isAlive == true),
        "lastLine" to lastLine,
        // Whether this plugin holds a tunnel: the child can only run while it does.
        "tun" to (cachedTun != null),
    )

    private fun start(token: Long, config: String): Map<String, Any> {
        stop()
        acknowledged = false
        val binary = binary() ?: return failure("libxray.so is missing from the APK")
        // The service publishes as its start returns; a cold start can arrive a few
        // milliseconds earlier than that, which is why this waits rather than assumes. A
        // later start — a tap on another node — reuses the tunnel it already has.
        val tun = tunForChild()
            ?: return failure("the portal has no tunnel yet: nothing established it")
        // A stop that arrived while the tunnel was being waited for wins: nothing is spawned.
        if (!isCurrent(token)) return cancelled()
        val document = runCatching { tunDocument(config, tun) }.getOrElse { error ->
            return failure("the node's config cannot take a tun inbound: ${error.message}")
        }
        val configFile = File(appContext.filesDir, "xray-tun.json")
        configFile.writeText(document, Charsets.UTF_8)
        val assets = installGeoAssets()

        return try {
            // Close-on-exec is a per-descriptor flag, so clearing it here is what lets the
            // child inherit the tunnel; the number is the same on both sides of exec. If it
            // cannot be cleared the child would start without a tunnel and die on its own
            // terms, so the start is refused here with the reason instead.
            if (!clearCloseOnExec(tun)) {
                return failure("cannot hand fd ${tun.fd} to the child: close-on-exec is stuck")
            }
            val builder = ProcessBuilder(binary.absolutePath, "run", "-c", configFile.absolutePath)
                .directory(appContext.filesDir)
                .redirectErrorStream(true)
            // The panel's config names rules as geosite:/geoip:, so the child needs the
            // data files. By default it looks next to the binary, where an APK cannot put
            // them, so the directory is stated explicitly.
            builder.environment()["XRAY_LOCATION_ASSET"] = assets.absolutePath
            builder.environment()[TUN_FD_ENV] = tun.fd.toString()
            val started = builder.start()
            process = started
            drain(started)

            val deadline = System.currentTimeMillis() + READY_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                // A newer command — a stop, or another start — owns the process from here.
                if (!isCurrent(token)) {
                    stop()
                    return cancelled()
                }
                if (!started.isAlive) {
                    val code = runCatching { started.exitValue() }.getOrDefault(-1)
                    stop()
                    return failure("xray exited with $code: $lastLine")
                }
                if (acknowledged) {
                    Log.i(TAG, "xray is reading the tunnel on fd ${tun.fd}")
                    return mapOf("ok" to true, "message" to "tunnel on fd ${tun.fd}")
                }
                // The wait belongs to the child: it returns the moment the child dies, so a
                // refused start does not sit out a poll interval before saying so.
                started.waitFor(POLL_MS, TimeUnit.MILLISECONDS)
            }
            stop()
            failure("xray did not take the tunnel within ${READY_TIMEOUT_MS}ms: $lastLine")
        } catch (e: Exception) {
            Log.e(TAG, "unable to start xray", e)
            stop()
            failure(e.message ?: "unable to start xray")
        }
    }

    /**
     * The node's configuration with the tunnel as its only entry point.
     *
     * The panel document is passed through as it is — outbounds, routing, dns — and only its
     * inbounds are replaced: a socks listener the panel declared would be a bridge into a
     * process that no longer has anyone on the other side, so it goes. The tun inbound states
     * the descriptor's number, the tunnel's addresses, and the interface to dial the node on.
     */
    private fun tunDocument(config: String, tun: XrayTun): String {
        val root = JSONObject(config)
        val inbounds = JSONArray()
        root.optJSONArray("inbounds")?.let { existing ->
            for (index in 0 until existing.length()) {
                val item = existing.optJSONObject(index) ?: continue
                if (item.optString("protocol") == "socks") continue
                inbounds.put(item)
            }
        }
        inbounds.put(
            JSONObject().apply {
                put("tag", TUN_INBOUND_TAG)
                put("protocol", "tun")
                put(
                    "settings",
                    JSONObject().apply {
                        put("name", TUN_NAME)
                        put("mtu", tun.mtu)
                        put("gateway", JSONArray(tun.gateway))
                        put("dns", JSONArray(tun.dns))
                        // The system routes are the VpnService's and are already in place:
                        // the child has no root to add its own, and must not try to.
                        put("autoSystemRoutingTable", false)
                        put("autoSystemDnsToGateway", false)
                        // Stated, not inferred: this is the one place the child's own
                        // transport is kept out of the tunnel it reads.
                        put("autoOutboundsInterface", tun.interfaceName)
                    },
                )
            },
        )
        root.put("inbounds", inbounds)
        // The acknowledgement this start waits for is an info-level line. A child that never
        // read the descriptor would otherwise be indistinguishable from one that did, which
        // is exactly the silent start this mode exists to avoid.
        val log = root.optJSONObject("log") ?: JSONObject()
        log.put("loglevel", ACK_LOG_LEVEL)
        root.put("log", log)
        return root.toString()
    }

    /// Copies the geodata shipped as assets next to the config, once per install.
    ///
    /// Xray reads geosite.dat and geoip.dat from XRAY_LOCATION_ASSET; putting them in
    /// filesDir keeps them readable to the child without shipping 10 MB in jniLibs, where
    /// only lib*.so survives packaging.
    private fun installGeoAssets(): File {
        val dir = File(appContext.filesDir, "xray-assets")
        if (!dir.exists()) dir.mkdirs()
        for (name in listOf("geosite.dat", "geoip.dat")) {
            val target = File(dir, name)
            val expected = runCatching {
                appContext.assets.open("flutter_assets/assets/xray/$name").use { it.readBytes().size }
            }.getOrDefault(0)
            if (target.exists() && target.length() == expected.toLong() && expected > 0) continue
            runCatching {
                appContext.assets.open("flutter_assets/assets/xray/$name").use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
            }.onFailure { Log.e(TAG, "cannot install $name: ${it.message}") }
        }
        return dir
    }

    /// The tunnel the child should read: a newly published one, else the one in hand.
    ///
    /// The service publishes exactly once per VPN start, so a fresh publish always wins; the
    /// cached descriptor is what a restart after a tap uses, since the interface behind it
    /// did not change.
    private fun tunForChild(): XrayTun? {
        XrayTunHolder.take()?.let { tun ->
            cachedTun = tun
            return tun
        }
        return cachedTun ?: XrayTunHolder.await(TUN_WAIT_MS)?.also { cachedTun = it }
    }

    private fun clearCloseOnExec(tun: XrayTun): Boolean =
        runCatching { Os.fcntlInt(tun.descriptor.fileDescriptor, OsConstants.F_SETFD, 0) }
            .onFailure { Log.w(TAG, "cannot clear close-on-exec on fd ${tun.fd}: ${it.message}") }
            .isSuccess

    private fun stop() {
        val current = killNow() ?: return
        reap(current)
    }

    /// Takes the child away from the plugin and terminates it, without waiting for it to
    /// go. Safe from any thread: the platform thread calls this so that a stop is not
    /// queued behind the start it is meant to interrupt.
    private fun killNow(): Process? {
        val current = process ?: return null
        process = null
        runCatching { current.destroy() }
        return current
    }

    /// Waits for a killed child to go, and insists when it does not.
    private fun reap(current: Process) {
        runCatching {
            if (!current.waitFor(3, TimeUnit.SECONDS)) {
                current.destroyForcibly()
                current.waitFor(2, TimeUnit.SECONDS)
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
        // A thread of its own, never the executor that runs start(): that one is still busy
        // waiting for the acknowledgement, so a queued drain would only run after the wait
        // ended — which both hides the child's output and can block it on a full pipe.
        Thread {
            runCatching {
                started.inputStream.bufferedReader(Charsets.UTF_8).useLines { lines ->
                    for (line in lines) {
                        lastLine = line
                        // The tunnel's own reader says so once it is up: that line is the
                        // proof the descriptor was accepted, not the fact the process lives.
                        if (line.contains(ACK_MARKER, ignoreCase = true)) {
                            acknowledged = true
                        }
                        if (line.contains("error", true) || line.contains("fatal", true)) {
                            Log.e(TAG, line)
                        } else {
                            Log.i(TAG, line)
                        }
                    }
                }
            }.onFailure { Log.w(TAG, "output stream closed: ${it.message}") }
        }.start()
    }

    private fun failure(message: String): Map<String, Any> =
        mapOf("ok" to false, "message" to message, "lastLine" to lastLine)

    /// A start cut short by a newer request says so, rather than reading as a refusal.
    private fun cancelled(): Map<String, Any> =
        mapOf(
            "ok" to false,
            "cancelled" to true,
            "message" to "start cancelled by a newer request",
            "lastLine" to lastLine,
        )

    private fun MethodChannel.invokeMethodOnMainThread(method: String, arguments: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            invokeMethod(method, arguments)
        }
    }

    companion object {
        private const val TAG = "XrayCore"
        private const val LIB_NAME = "libxray.so"
        private const val READY_TIMEOUT_MS = 12_000L
        private const val POLL_MS = 200L

        /// How long the plugin waits for the service to publish the tunnel it just made.
        private const val TUN_WAIT_MS = 8_000L

        /// The environment variable the bundled Xray reads its tun descriptor from.
        private const val TUN_FD_ENV = "xray.tun.fd"

        /// The line the tun stack prints once its reader is up.
        private const val ACK_MARKER = "TUN reader - started"

        /// Info, not the panel's level: without it the acknowledgement line is filtered out.
        private const val ACK_LOG_LEVEL = "info"

        private const val TUN_NAME = "portal0"
        private const val TUN_INBOUND_TAG = "tun-in"

        val CHANNEL = "${Components.PACKAGE_NAME}/xray"
    }
}
