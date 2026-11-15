package com.follow.clashx.plugins

import android.content.Context
import android.system.Os
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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/**
 * Runs the bundled Xray on the simple portal's tunnel.
 *
 * The VpnService establishes the tun — no other component can — and the core reads that very
 * descriptor. The core is a c-shared library in this process, not a child: `XrayStart` sets
 * the descriptor on the core's own tun device, so nothing crosses a process boundary and
 * nothing has to survive one. An exec'd child could not read the tunnel at all: `Runtime.exec`
 * spawns with close-on-exec set on every descriptor, so the child started without the tun and
 * died with "bad file descriptor" before it logged a line.
 *
 * There is no engine in front of it and no socks bridge behind it: the system routes packets
 * into the tun, the core reads them, and the node it dials is the one the owner picked.
 *
 * The start is only a success once the core has said it is reading the tunnel in its own log;
 * a core that refuses the document, or one that never takes the descriptor, fails the start
 * with its own words instead of falling back to a bridge it no longer has.
 *
 * Protecting the core's transport: every outbound is bound to the interface the tunnel rides
 * on, stated as `autoOutboundsInterface`; the service resolves that interface and refuses to
 * hand over a tunnel without one. Being in-process would allow `VpnService.protect`, but the
 * binding is what states the intent, so it stays.
 */
class XrayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val executor = Executors.newSingleThreadExecutor()

    /// Whether the core holds the tunnel right now.
    ///
    /// An in-process core has no handle to poll: the native start returning is not the same
    /// as the core reading the tun, and there is no process that dies to tell the two apart.
    /// The flag is set when the core accepted the document and cleared by the first stop, and
    /// the acknowledgement in the log is what decides whether the start may keep it.
    @Volatile private var coreRunning = false
    @Volatile private var lastLine: String = ""

    /// Set once the library is open and its three entry points resolve.
    @Volatile private var libraryLoaded = false

    /// Why the library is not usable, if it is not: a start reports this instead of throwing.
    @Volatile private var libraryProblem: String? = null

    /// The tunnel this plugin was handed, kept for the life of the VPN.
    ///
    /// The service publishes it once, when it establishes the interface; the core is
    /// restarted on every pick, and each restart reads the same descriptor. Taking it once
    /// and keeping it is what lets a tap replace the core without replacing the tunnel.
    @Volatile private var cachedTun: XrayTun? = null

    /// Every command takes a number; only the newest one may touch the core.
    ///
    /// A stop has to invalidate a start that is already waiting *and* one still queued
    /// behind it on the executor, which a shared boolean cannot do: the queued start would
    /// clear it and go on to open a core nobody asked for any more. The number only ever
    /// grows, so an older command compares false wherever it wakes up.
    private val operation = AtomicLong(0)

    private fun nextOperation(): Long = operation.incrementAndGet()

    private fun isCurrent(token: Long): Boolean = operation.get() == token

    /// The core's C API, as exported by the c-shared library that ships in jniLibs.
    ///
    /// [XrayStart] sets `xray.tun.fd` on the core's own tun device, starts it, and answers
    /// null on success or the core's error text. The descriptor is this process's, so the
    /// number means the same thing on both sides of the call — which is the whole reason the
    /// core is loaded instead of spawned.
    private external fun XrayStart(config: String, tunFd: Int): String?

    private external fun XrayStop()

    private external fun XrayVersion(): String?

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        // The service takes the core down with the tunnel, so a revoked VPN cannot leave a
        // core reading a descriptor nobody answers for. Taking a number first also cancels
        // any start the service's teardown interrupted before it could open the core.
        XrayChildControl.stop = {
            nextOperation()
            // The service is closing the descriptor it owns: the tunnel in hand is gone with
            // it, and so is whatever is reading it. Called on the service's own thread, so
            // record the loss and return — the native stop is queued, not run here.
            cachedTun = null
            takeCore()
            requestNativeStop()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        XrayChildControl.stop = null
        nextOperation()
        takeCore()
        requestNativeStop()
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
                // arrival: the newest command is the one that owns the core.
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
                // Take the number first: that is what makes a start — waiting already, or
                // still queued behind this one — abandon its work instead of overriding the
                // stop. The native stop is queued rather than run here, so the caller is not
                // held for the core's wind-down; a start in flight ends on its own when it
                // sees the new number, which is also when the queue reaches this task.
                val token = nextOperation()
                takeCore()
                requestNativeStop()
                executor.execute {
                    // The report follows the stop, whatever arrived in between: what it says
                    // is the state after the core was asked to go.
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
        "running" to coreRunning,
        "lastLine" to lastLine,
        // Whether this plugin holds a tunnel: the core can only run while it does.
        "tun" to (cachedTun != null),
    )

    private fun start(token: Long, config: String): Map<String, Any> {
        // One core at a time: a restart after a tap replaces the core that is reading the
        // tunnel, and two cores cannot share one descriptor.
        stopCoreHere()
        // The service publishes as its start returns; a cold start can arrive a few
        // milliseconds earlier than that, which is why this waits rather than assumes. A
        // later start — a tap on another node — reuses the tunnel it already has.
        val tun = tunForChild()
            ?: return failure("the portal has no tunnel yet: nothing established it")
        // A stop that arrived while the tunnel was being waited for wins: nothing opens.
        if (!isCurrent(token)) return cancelled()
        val logFile = File(appContext.filesDir, LOG_NAME)
        val document = runCatching { tunDocument(config, tun, logFile) }.getOrElse { error ->
            return failure("the node's config cannot take a tun inbound: ${error.message}")
        }
        val configFile = File(appContext.filesDir, CONFIG_NAME)
        runCatching { configFile.writeText(document, Charsets.UTF_8) }.onFailure { error ->
            return failure("cannot write ${configFile.name}: ${error.message}")
        }
        // The panel's config names rules as geosite:/geoip:, and the core looks for the data
        // files under XRAY_LOCATION_ASSET. The variable has to be set before the library is
        // opened, because the Go runtime copies the environment when the library loads.
        val assets = installGeoAssets()
        runCatching { Os.setenv(ASSET_ENV, assets.absolutePath, true) }
            .onFailure { Log.w(TAG, "cannot point xray at ${assets.absolutePath}: ${it.message}") }
        ensureLibrary()?.let { problem -> return failure(problem) }
        // A line left by the previous start must not acknowledge this one.
        runCatching { logFile.writeText("") }

        val attempt = runCatching { XrayStart(document, tun.fd) }
        if (attempt.isFailure) {
            val error = attempt.exceptionOrNull()
            Log.e(TAG, "unable to start xray", error)
            lastLine = error?.message ?: "unable to start xray"
            return failure(lastLine)
        }
        val nativeError = attempt.getOrNull()
        if (nativeError != null) {
            // The library's own words: the core refused the document, or could not take the
            // descriptor. There is no child left to ask and no exit code to read.
            lastLine = nativeError
            Log.e(TAG, "xray refused the start: $nativeError")
            return failure(nativeError)
        }
        coreRunning = true
        lastLine = ""
        return try {
            awaitAck(token, tun, logFile)
        } catch (e: Exception) {
            Log.e(TAG, "unable to start xray", e)
            stopCoreHere()
            failure(e.message ?: "unable to start xray")
        }
    }

    /**
     * The node's configuration with the tunnel as its only entry point.
     *
     * The panel document is passed through as it is — outbounds, routing, dns — and only its
     * inbounds are replaced: a socks listener the panel declared would be a bridge into a
     * core that no longer has anyone on the other side, so it goes. The tun inbound states
     * the descriptor's number, the tunnel's addresses, and the interface to dial the node on.
     */
    private fun tunDocument(config: String, tun: XrayTun, logFile: File): String {
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
                        // the core has no root to add its own, and must not try to.
                        //
                        // `autoSystemRoutingTable` is absent on purpose: in this core's schema
                        // it is a []string of routes to take over, not a flag, so a boolean
                        // makes the core refuse the whole config
                        // ("cannot unmarshal bool into ... TunConfig.autoSystemRoutingTable of
                        // type []string"). An empty list is the same as leaving it out.
                        put("autoSystemDnsToGateway", false)
                        // Stated, not inferred: this is the one place the core's own
                        // transport is kept out of the tunnel it reads.
                        put("autoOutboundsInterface", tun.interfaceName)
                    },
                )
            },
        )
        root.put("inbounds", inbounds)
        // The acknowledgement this start waits for is an info-level line, and it is only
        // written if the core logs at all — the panel's own level may filter it out. `error`
        // is the core's general log; `access` records requests, which is not what a start
        // reads. A file rather than the console: the plugin has to read the core's line, not
        // only have it appear in logcat.
        val log = root.optJSONObject("log") ?: JSONObject()
        log.put("loglevel", ACK_LOG_LEVEL)
        log.put("error", logFile.absolutePath)
        root.put("log", log)
        return root.toString()
    }

    /// Copies the geodata shipped as assets into filesDir, once per install.
    ///
    /// Xray reads geosite.dat and geoip.dat from XRAY_LOCATION_ASSET, and an APK cannot put
    /// them next to the library: filesDir is where the core can open them, so they go there
    /// and the variable above points at the directory.
    private fun installGeoAssets(): File {
        val dir = File(appContext.filesDir, GEODATA_DIR)
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

    /// The tunnel the core should read: a newly published one, else the one in hand.
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

    /// Waits for the core's own line that says the tunnel is being read.
    ///
    /// The core runs in this process, so there is no output stream to drain and no exit code
    /// to read. What it writes to the log the document names is the only evidence: the tun
    /// reader says it started, or an `[Error]` line says it never will. Both end the wait —
    /// one as the acknowledgement, one as the failure, each with the core's own words.
    private fun awaitAck(token: Long, tun: XrayTun, logFile: File): Map<String, Any> {
        val tail = LogTail(logFile)
        val deadline = System.currentTimeMillis() + READY_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            // A newer command — a stop, or another start — owns the core from here.
            if (!isCurrent(token)) {
                stopCoreHere()
                return cancelled()
            }
            for (line in tail.poll()) {
                if (line.isBlank()) continue
                lastLine = line.trim()
                // The reader's start line is the proof, in either spelling the core prints.
                // A failure line answers the start now, not at the deadline: a refused
                // document would otherwise sit out the whole timeout saying nothing.
                if (ACK_MARKERS.any { lastLine.contains(it, ignoreCase = true) }) {
                    Log.i(TAG, "xray is reading the tunnel on fd ${tun.fd}")
                    return mapOf("ok" to true, "message" to "tunnel on fd ${tun.fd}")
                }
                if (isCoreError(lastLine)) {
                    Log.e(TAG, "xray failed to take the tunnel: $lastLine")
                    stopCoreHere()
                    return failure(lastLine)
                }
            }
            // The interval is slept, not spun: a stop that arrives in the middle of it ends
            // the wait on the next slice instead of after a whole poll.
            if (!pauseUnlessCancelled(token)) {
                stopCoreHere()
                return cancelled()
            }
        }
        stopCoreHere()
        return failure("xray did not take the tunnel within ${READY_TIMEOUT_MS}ms: $lastLine")
    }

    /// Reads the log the document names, one appended line at a time.
    ///
    /// The plugin and the core are one process, so this file is the channel between them:
    /// the offset is kept between polls, a line is parsed once, and a write caught in the
    /// middle of a line is completed by the next read instead of being decoded twice.
    private class LogTail(private val file: File) {
        private var offset = 0L
        private val pending = ByteArrayOutputStream()

        fun poll(): List<String> {
            val lines = ArrayList<String>()
            runCatching {
                if (!file.exists()) return@runCatching
                RandomAccessFile(file, "r").use { log ->
                    // The start that opened this log truncated it; an offset past its end no
                    // longer means anything, so reading starts over.
                    if (log.length() < offset) {
                        offset = 0
                        pending.reset()
                    }
                    log.seek(offset)
                    val buffer = ByteArray(8 * 1024)
                    while (true) {
                        val read = log.read(buffer)
                        if (read <= 0) break
                        offset += read
                        pending.write(buffer, 0, read)
                    }
                }
                val bytes = pending.toByteArray()
                var start = 0
                for (index in bytes.indices) {
                    if (bytes[index] != '\n'.code.toByte()) continue
                    lines.add(String(bytes, start, index - start, Charsets.UTF_8).trimEnd('\r'))
                    start = index + 1
                }
                pending.reset()
                if (start < bytes.size) pending.write(bytes, start, bytes.size - start)
            }.onFailure { Log.w(TAG, "cannot read ${file.name}: ${it.message}") }
            return lines
        }
    }

    /// Whether the core said it cannot go on. Its own log prefixes the level in brackets, and
    /// the line it prints when a start is refused carries none of them.
    private fun isCoreError(line: String): Boolean =
        line.contains("[error]", ignoreCase = true) ||
            line.contains("[fatal]", ignoreCase = true) ||
            line.startsWith("failed to start", ignoreCase = true)

    /// Sleeps one poll interval in slices, and answers whether the command is still current.
    private fun pauseUnlessCancelled(token: Long): Boolean {
        val until = System.currentTimeMillis() + POLL_MS
        while (System.currentTimeMillis() < until) {
            if (!isCurrent(token)) return false
            Thread.sleep(POLL_SLICE_MS)
        }
        return isCurrent(token)
    }

    /// Opens the core library once, and answers with what a start should say when it cannot.
    private fun ensureLibrary(): String? {
        if (libraryLoaded) return null
        libraryProblem?.let { return it }
        synchronized(this) {
            if (libraryLoaded) return null
            libraryProblem?.let { return it }
            val problem = loadLibrary()
            if (problem == null) {
                libraryLoaded = true
            } else {
                libraryProblem = problem
            }
            return problem
        }
    }

    /// `System.loadLibrary` plus a call that proves the entry points are there.
    ///
    /// Guarded, because a missing library must read as a build that cannot do it rather than
    /// crash the thread that asked. The first call into the library is what resolves its
    /// symbols, so it is made here: a library that loads but does not export the three JNI
    /// names would otherwise fail inside a start, where it reads as a core refusing a config.
    private fun loadLibrary(): String? {
        runCatching { System.loadLibrary(LIB_NAME) }.onFailure { error ->
            Log.e(TAG, "$UNAVAILABLE: ${error.message}")
            return UNAVAILABLE
        }
        val version = runCatching { XrayVersion() }.getOrElse { error ->
            Log.e(TAG, "$NO_ENTRY_POINTS: ${error.message}")
            return NO_ENTRY_POINTS
        }
        Log.i(TAG, "xray ${version ?: "?"} is loaded in this process")
        return null
    }

    /// Marks the core as gone, whoever asks: the flag is what a start checks, and the
    /// invalidation has to happen on the thread that owns the decision, not on the queue.
    private fun takeCore(): Boolean {
        val was = coreRunning
        coreRunning = false
        return was
    }

    /// Asks the core to stop on the calling thread.
    ///
    /// This is the path a start takes: it already owns the executor slot, so the native call
    /// belongs here rather than queued behind itself. `XrayStop` returns once the core has let
    /// go of its tunnels; there is no process to wait for, so the old destroy-then-force pair
    /// has nothing left to do.
    private fun stopCoreHere() {
        if (!takeCore()) return
        if (!libraryLoaded) return
        runCatching { XrayStop() }.onFailure { Log.w(TAG, "stop: ${it.message}") }
    }

    /// Hands `XrayStop` to the executor and returns at once.
    ///
    /// Starts are queued on the same single thread, so the native stop can never overlap an
    /// `XrayStart`, and the caller — a tap, or the service closing its tunnel — is not held
    /// for the core's lifetime. It is queued even when this plugin believes nothing runs: a
    /// start in flight may have just opened a core, and a stop with nothing running is a
    /// no-op on the other side.
    private fun requestNativeStop() {
        executor.execute {
            if (!libraryLoaded) return@execute
            runCatching { XrayStop() }.onFailure { Log.w(TAG, "stop: ${it.message}") }
        }
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

        /// The library as `System.loadLibrary` names it: it adds the `lib` prefix and `.so`.
        private const val LIB_NAME = "xray"

        private const val READY_TIMEOUT_MS = 12_000L

        /// How often the log is read, and how finely a sleep is cut so a stop does not wait
        /// out a whole interval before the start gives up.
        private const val POLL_MS = 200L
        private const val POLL_SLICE_MS = 50L

        /// How long the plugin waits for the service to publish the tunnel it just made.
        private const val TUN_WAIT_MS = 8_000L

        /// The document the core is started from, and the log this start reads.
        private const val CONFIG_NAME = "xray-tun.json"
        private const val LOG_NAME = "xray.log"

        /// The directory the geodata files are installed into, and the core's variable for it.
        private const val GEODATA_DIR = "xray-assets"
        private const val ASSET_ENV = "XRAY_LOCATION_ASSET"

        /// What a start answers when the build carries no usable core.
        private const val UNAVAILABLE = "xray is not available in this build"
        private const val NO_ENTRY_POINTS = "libxray.so is missing its JNI entry points"

        /// The lines the tun stack prints once its reader is up: the stack's own start line,
        /// and the one the Android reader logs when it has taken the descriptor. Either is
        /// proof; a core that never prints one is a core that never read the tun.
        private val ACK_MARKERS = listOf("TUN reader - started", "read Android Tun Fd")

        /// Info, not the panel's level: without it the acknowledgement line is filtered out.
        private const val ACK_LOG_LEVEL = "info"

        private const val TUN_NAME = "portal0"
        private const val TUN_INBOUND_TAG = "tun-in"

        val CHANNEL = "${Components.PACKAGE_NAME}/xray"
    }
}
