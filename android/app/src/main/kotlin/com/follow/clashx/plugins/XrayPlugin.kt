package com.follow.clashx.plugins

import android.content.Context
import android.system.Os
import android.util.Log
import com.follow.clashx.PortalChildGateway
import com.follow.clashx.PortalChildStart
import com.follow.clashx.PortalChildStop
import com.follow.clashx.PortalRuntimeCoordinator
import com.follow.clashx.common.Components
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalRuntimeState
import com.follow.clashx.common.PortalMeasureBridge
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
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.launch

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
 * Keeping the core's transport out of its own tunnel is the VpnService's job, not the
 * document's: the service adds this app's package to `addDisallowedApplication`, so the system
 * installs no route into the tun for this uid and every socket the core opens leaves by the
 * underlying network. That is the Android-native substitute for binding outbounds to an
 * interface, and the only one available here: `autoOutboundsInterface` makes the core resolve
 * the interface with `net.InterfaceByName`, which reads the interface table over rtnetlink,
 * and an app uid is denied that read (`netlinkrib: permission denied`). The exclusion is by
 * uid, exactly like `VpnService.protect`, and it needs no interface name at all.
 */
class XrayPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, PortalChildGateway {
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
    private external fun XrayStart(config: String, tunFd: Int, assetDir: String): String?

    private external fun XrayStop()

    private external fun XrayVersion(): String?

    /// Times every node of a document in the measurement's own instance.
    ///
    /// The answer is JSON: `{"rows":[{"tag","delay","error"}]}`, delay in milliseconds,
    /// -1 failed and -2 timed out. The measurement has its own core slot, so a sweep runs
    /// while the portal's child keeps reading the tunnel.
    private external fun XrayMeasure(
        config: String,
        tags: String,
        url: String,
        timeoutMs: Int,
        limit: Int,
    ): String?

    /// Closes the measurement instance and leaves the tunnel's alone.
    private external fun XrayMeasureStop()

    /// The running core's own latency numbers. It measures nothing here: the document declares a
    /// burst observatory, the core times every node on its own period, and this reads what the
    /// core already knows — the same way a mihomo panel reads url-test history.
    private external fun XrayObservatory(): String?

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        // The service takes the core down with the tunnel, so a revoked VPN cannot leave a
        // core reading a descriptor nobody answers for. Taking a number first also cancels
        // any start the service's teardown interrupted before it could open the core.
        // The dashboard speaks to the portal channel, the core lives here: the bridge is the
        // one line between them, and it is only set while this plugin holds the library.
        PortalMeasureBridge.start = { config, tags, url, timeoutMs, limit ->
            val task = executor.submit(Callable { measure(config, tags, url, timeoutMs, limit) })
            try {
                task.get(MEASURE_WAIT_MS, TimeUnit.MILLISECONDS)
            } catch (error: Exception) {
                task.cancel(true)
                mapOf("ok" to false, "message" to (error.message ?: "$error"))
            }
        }
        PortalMeasureBridge.stop = {
            val task = executor.submit(Callable { stopMeasure() })
            runCatching { task.get(STOP_WAIT_MS, TimeUnit.MILLISECONDS) }.getOrDefault(false)
        }
        XrayChildControl.stop = {
            nextOperation()
            // The service is closing the descriptor it owns: the tunnel in hand is gone with
            // it, and so is whatever is reading it. Called on the service's own thread, so
            // record the loss and return — the native stop is queued, not run here.
            cachedTun = null
            takeCore()
            requestNativeStop()
        }
        // The coordinator's child half: starts and stops that only answer once the core has.
        PortalRuntimeCoordinator.attachChild(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        PortalRuntimeCoordinator.detachChild(this)
        XrayChildControl.stop = null
        PortalMeasureBridge.start = null
        PortalMeasureBridge.stop = null
        nextOperation()
        takeCore()
        requestNativeStop()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(status())
            // The core's own numbers, read not measured: cheap enough to ask every few seconds.
            "observatory" -> result.success(observatory())
            // The channel is not a second way into the core: it is the same entry the mode
            // switch and Quick Settings take, so the same mutex and the same generation
            // decide the order. The plugin still answers with its own words.
            "start" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrBlank()) {
                    result.success(failure("empty config"))
                    return
                }
                GlobalState.launch {
                    val outcome = PortalRuntimeCoordinator.startChild(config)
                    channel.invokeMethodOnMainThread("state", status())
                    replyOnMain(result, outcome.toMap())
                }
            }
            "stop" -> GlobalState.launch {
                // Returns after `XrayStop` has returned: a stop that did not happen is not
                // reported as one, which is what makes the next start's evidence meaningful.
                val outcome = PortalRuntimeCoordinator.close("plugin-stop")
                channel.invokeMethodOnMainThread("state", status())
                replyOnMain(
                result,
                mapOf(
                    "ok" to outcome.ok,
                    "cancelled" to outcome.cancelled,
                    "message" to outcome.reason.ifEmpty { "stopped" },
                    "generation" to outcome.runtime.generation,
                ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun status(): Map<String, Any> = mapOf(
        "running" to coreRunning,
        "lastLine" to lastLine,
        // Whether this plugin holds a tunnel: the core can only run while it does.
        "tun" to (cachedTun != null),
        // The record this core belongs to: a `running` flag without it cannot say whether
        // the answer still describes the portal on screen.
        "generation" to PortalRuntimeState.current().generation,
        "phase" to PortalRuntimeState.current().phase,
        "fdEpoch" to (cachedTun?.epoch ?: 0L),
    )

    private fun replyOnMain(result: MethodChannel.Result, value: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { result.success(value) }
        }
    }

    override fun start(config: String): PortalChildStart {
        val token = nextOperation()
        val task = executor.submit(Callable { start(token, config) })
        val outcome = try {
            task.get(START_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (error: TimeoutException) {
            nextOperation()
            task.cancel(true)
            return PortalChildStart(
                ok = false,
                reason = "the core did not answer within ${START_WAIT_MS}ms: $lastLine",
            )
        } catch (error: Exception) {
            return PortalChildStart(ok = false, reason = error.message ?: "$error")
        }
        val ok = outcome["ok"] == true
        return PortalChildStart(
            ok = ok,
            cancelled = outcome["cancelled"] == true,
            reason = if (ok) "" else (outcome["message"] as? String).orEmpty(),
            epoch = (outcome["epoch"] as? Long) ?: 0L,
        )
    }

    /// Stops the core, and answers only after `XrayStop` returned.
    ///
    /// The flag is taken on the calling thread — that is what makes a start that is still
    /// waiting see a newer command — and the native call is queued behind whatever the
    /// executor is doing, then waited for. Its own failure is reported as a failure: the
    /// plugin used to answer `ok` for a stop that was merely enqueued.
    override fun stop(): PortalChildStop {
        val token = nextOperation()
        val wasRunning = takeCore()
        val task = executor.submit(Callable {
            if (!wasRunning || !libraryLoaded) return@Callable Result.success(Unit)
            runCatching { XrayStop() }
        })
        val outcome = try {
            task.get(STOP_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (error: TimeoutException) {
            task.cancel(true)
            return PortalChildStop(
                ok = false,
                reason = "XrayStop did not return within ${STOP_WAIT_MS}ms",
            )
        } catch (error: Exception) {
            return PortalChildStop(ok = false, reason = error.message ?: "$error")
        }
        val problem = outcome.exceptionOrNull()
        Log.i(
            TAG,
            "stop owner=Xray token=$token wasRunning=$wasRunning xraystop=${problem?.message ?: "ok"}",
        )
        return if (problem == null) {
            PortalChildStop(ok = true)
        } else {
            PortalChildStop(ok = false, reason = "${problem.message}")
        }
    }

    override val running: Boolean get() = coreRunning

    override val coreLine: String get() = lastLine

    private fun start(token: Long, config: String): Map<String, Any> {
        // One core at a time: a restart after a tap replaces the core that is reading the
        // tunnel, and two cores cannot share one descriptor.
        stopCoreHere()
        // The service publishes as its start returns; a cold start can arrive a few
        // milliseconds earlier than that, which is why this waits rather than assumes. A
        // later start — a tap on another node — reuses the tunnel it already has.
        val tun = tunForChild()
            ?: return failure("the portal has no open tunnel: the VPN that owns it is not up")
        // A stop that arrived while the tunnel was being waited for wins: nothing opens.
        if (!isCurrent(token)) return cancelled()
        // The descriptor, not merely its number: a tunnel the service closed between the take
        // and this line reports -1 (and 0..2 are the standard streams), while its number may
        // already belong to the next file the process opened. proxy/tun would then ioctl that
        // file and report the ioctl, not the cause.
        if (tun.fd < XrayTun.FIRST_TUN_FD || !tun.descriptor.fileDescriptor.valid()) {
            cachedTun = null
            XrayTunHolder.clear()
            return failure("the tunnel descriptor is closed: nothing to read")
        }
        // The core's own log, in the directory adb can read: `filesDir` is unreadable on a
        // release build, which is why a refused start on the phone could only be described.
        // Named in full on purpose: this file's only business with the telemetry is this path.
        val logFile = com.follow.clashx.common.PortalTelemetry.xrayFile
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

        // The core gets a descriptor this start owns. The service may close its tunnel at any
        // moment — a mode switch, a new establish — and a number that closed between the check
        // above and the core's own read is precisely how the core came to ioctl stdin.
        // Duplicating it here makes the number outlive the service's close for as long as this
        // call runs; the core duplicates it once more for itself (proxy/tun does
        // F_DUPFD_CLOEXEC on what it is handed), so closing this one on the way out leaves the
        // core reading its own.
        //
        // `XrayTun.duplicate()` is the only way to it: it asks the descriptor whether it is
        // still open under the same guard as the duplicate, so a tunnel the service closed in
        // between answers `null` here instead of throwing `Already closed` out of `dup()`.
        val handoff = tun.duplicate() ?: run {
            cachedTun = null
            XrayTunHolder.clear(tun.epoch)
            return failure("the tunnel descriptor is closed: nothing to read")
        }
        val fd = handoff.fd
        Log.i(TAG, "handing tun fd $fd (a duplicate of ${tun.fd}, epoch ${tun.epoch}) to the core")
        val attempt = try {
            runCatching { XrayStart(document, fd, assets.absolutePath) }
        } finally {
            runCatching { handoff.close() }
        }
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
            awaitAck(token, fd, logFile, tun.epoch)
        } catch (e: Exception) {
            Log.e(TAG, "unable to start xray", e)
            stopCoreHere()
            failure(e.message ?: "unable to start xray")
        }
    }


    /// Times every node of [config] in the measurement's own core instance.
    ///
    /// This is the whole sweep: one document whose outbounds are the nodes, one tag list, one
    /// call. Nothing listens, so there is no port to hand over and nothing for Dart to speak;
    /// the tunnel's instance is not touched, which is what lets a sweep run beside an open
    /// portal. Answers JSON: `{"rows":[{tag,delay,error}]}` or `{"error":...}`.
    private fun measure(
        config: String,
        tags: String,
        url: String,
        timeoutMs: Int,
        limit: Int,
    ): Map<String, Any> {
        ensureLibrary()?.let { problem ->
            return mapOf("ok" to false, "message" to problem)
        }
        val answer = runCatching { XrayMeasure(config, tags, url, timeoutMs, limit) }
            .getOrElse { error ->
                Log.e(TAG, "measurement raised", error)
                return mapOf("ok" to false, "message" to (error.message ?: "$error"))
            }
            ?: return mapOf("ok" to false, "message" to "no answer from the core")
        return mapOf("ok" to true, "message" to "", "rows" to answer)
    }

    /// What the tunnel's own core has timed so far, as JSON, without measuring anything.
    private fun observatory(): Map<String, Any> {
        ensureLibrary()?.let { problem ->
            return mapOf("ok" to false, "message" to problem)
        }
        val answer = runCatching { XrayObservatory() }
            .getOrElse { error ->
                Log.e(TAG, "observatory raised", error)
                return mapOf("ok" to false, "message" to (error.message ?: "$error"))
            }
            ?: return mapOf("ok" to false, "message" to "no answer from the core")
        return mapOf("ok" to true, "message" to "", "rows" to answer)
    }

    /// Closes the measurement instance, if one is running. The tunnel's core is not stopped.
    private fun stopMeasure(): Boolean {
        if (!libraryLoaded) return false
        return runCatching {
            XrayMeasureStop()
            true
        }.getOrElse { error ->
            Log.w(TAG, "measurement stop raised: ${error.message}")
            false
        }
    }

    /**
     * The node's configuration with the tunnel as its only entry point.
     *
     * The panel document is passed through as it is — outbounds, routing, dns — and only its
     * inbounds are replaced: a socks listener the panel declared would be a bridge into a
     * core that no longer has anyone on the other side, so it goes. The tun inbound states
     * the descriptor's number and the tunnel's addresses. It states no outbound interface:
     * see the class comment — the core would have to enumerate interfaces to resolve one, and
     * the service keeps this app out of the tunnel by uid instead.
     */
    private fun tunDocument(config: String, tun: XrayTun, logFile: File): String {
        val root = JSONObject(config)
        val inbounds = JSONArray()
        // A panel's own listeners are not ours to keep. Whatever the document declares as an
        // entry point — socks, http, mixed, dokodemo, anything else — would be a port this app
        // opens on the phone on the provider's terms, and an inbound without credentials is an
        // open relay to whoever can reach it. The tunnel is the only way in that this app
        // needs, so every declared inbound goes; the tun inbound below is put in its place.
        // Linux and Android both reach 127.0.0.1 from other apps, so "it listens on loopback"
        // is not a protection either.
        val dropped = mutableListOf<String>()
        root.optJSONArray("inbounds")?.let { existing ->
            for (index in 0 until existing.length()) {
                val item = existing.optJSONObject(index) ?: continue
                val protocol = item.optString("protocol").ifEmpty { "?" }
                dropped.add("$protocol@${item.optString("listen")}")
            }
        }
        if (dropped.isNotEmpty()) {
            Log.i(TAG, "inbounds from the subscription are dropped: ${dropped.joinToString(", ")}")
        }
        inbounds.put(
            JSONObject().apply {
                put("tag", TUN_INBOUND_TAG)
                put("protocol", "tun")
                put(
                    "settings",
                    JSONObject().apply {
                        // Four keys, and nothing else, is the whole document this core can be
                        // given on Android without it reading the interface table:
                        //  - `name` must stay non-empty. An empty one sends
                        //    infra/conf/tun.go to GetAvailableTunName(), which calls
                        //    net.Interfaces() — the same netlink read the core is denied, one
                        //    step earlier, at config build.
                        //  - `autoSystemRoutingTable` must never be emitted. It is a []string of
                        //    routes in this schema, not a flag, so a boolean refuses the whole
                        //    config; and a non-empty list implies `autoOutboundsInterface: auto`,
                        //    which resolves through net.InterfaceByName.
                        //  - `autoOutboundsInterface` must never be emitted, for that reason.
                        //    See the class comment: the uid exclusion is what keeps the core's
                        //    transport out of the tunnel.
                        //  - `autoSystemWfpBlockLeak` and `autoSystemDnsToGateway` are system
                        //    takeovers: the first is Windows' firewall, and the second has no
                        //    implementation on Android (proxy/tun's Android reader exposes no
                        //    ConfigureSystemDNS), so it can only be checked, never honoured.
                        //  - The system routes are the VpnService's and are already in place: the
                        //    core has no root to add its own, and must not try to.
                        put("name", TUN_NAME)
                        put("mtu", tun.mtu)
                        put("gateway", JSONArray(tun.gateway))
                        put("dns", JSONArray(tun.dns))
                    },
                )
            },
        )
        root.put("inbounds", inbounds)
        // The tunnel's DNS is the core's own business: the VpnService hands every resolver
        // query to 198.18.0.2:53, and the core must answer it with its DNS module instead of
        // routing the packet somewhere that cannot exist.
        hijackTunnelDns(root)
        // A document that carries an observatory or a balancer asks the core to keep notes on
        // its own outbounds. Two pieces make that work inside a tunnel and neither is the
        // panel's business to get right:
        //  - `stats`, an empty object: the burst observatory reports into it, and a document
        //    that names `burstObservatory` without it is refused by the core at build.
        //  - a direct rule for the DNS servers' own addresses. The DNS module resolves names
        //    through the `dns` outbound, whose queries are ordinary connections to those
        //    addresses; without the rule they come back into the router, are handed to the
        //    balancer, and the balancer's health check asks DNS again — a loop that answers
        //    nothing and looks like a dead node.
        prepareObservatory(root)
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

    /// Makes the document answer its own DNS inside the tunnel.
    ///
    /// The service gives every app the resolver `198.18.0.2` (see `VpnService`), so the
    /// packets a name lookup produces arrive at the core as ordinary connections to
    /// `198.18.0.2:53`. A panel document has no reason to hijack that address: its own DNS
    /// section is written for a machine where the system resolver is real, and its routing
    /// sends port 53 wherever it sends everything else. The result on the phone is a query
    /// handed to `direct` for an address nothing answers — `[tun-in -> direct] …
    /// 198.18.0.2:53` in the core's log — and every name lookup sits there until it times
    /// out. That is exactly what the panel's balancer document did, and why 'Авто-выбор'
    /// resolved nothing while a concrete node seemed to work.
    ///
    /// Three things make it resolve, and none of them touch the node:
    ///  1. a `dns` section with at least one server the module can actually query;
    ///  2. one outbound of protocol `dns` — the document's own if it already has one, else
    ///     one appended under a tag of ours;
    ///  3. a routing rule, first in the list, that sends the tunnel inbound's port 53 to it.
    ///
    /// Rewritten rather than refused. A document whose DNS cannot be hijacked is not
    /// unusable — it is a document that has not been told what the tunnel is — and refusing
    /// it would fall back to a single node, which silently turns 'Авто-выбор' into "the
    /// first server" and loses the balancer the owner picked. The rewrite keeps a concrete
    /// node working exactly as it did (the same rule applies to it) and makes the balancer
    /// pick behave like one.
    private fun hijackTunnelDns(root: JSONObject) {
        val dns = root.optJSONObject("dns") ?: JSONObject().also { root.put("dns", it) }
        val servers = dns.optJSONArray("servers")
        if (servers == null || servers.length() == 0) {
            // No resolver of the panel's own: two anycast resolvers are enough to answer,
            // and their own traffic leaves by whatever the document routes.
            dns.put("servers", JSONArray(listOf(FALLBACK_DNS_1, FALLBACK_DNS_2)))
        }

        val outbounds = root.optJSONArray("outbounds") ?: JSONArray().also { root.put("outbounds", it) }
        var dnsTag: String? = null
        for (index in 0 until outbounds.length()) {
            val item = outbounds.optJSONObject(index) ?: continue
            if (!item.optString("protocol").equals("dns", ignoreCase = true)) continue
            val tag = item.optString("tag")
            if (tag.isEmpty()) {
                item.put("tag", DNS_OUTBOUND_TAG)
                dnsTag = DNS_OUTBOUND_TAG
            } else {
                dnsTag = tag
            }
            break
        }
        if (dnsTag == null) {
            dnsTag = DNS_OUTBOUND_TAG
            outbounds.put(
                JSONObject().apply {
                    put("tag", dnsTag)
                    put("protocol", "dns")
                },
            )
        }

        val routing = root.optJSONObject("routing") ?: JSONObject().also { root.put("routing", it) }
        val existing = routing.optJSONArray("rules") ?: JSONArray()
        val rules = JSONArray()
        rules.put(
            JSONObject().apply {
                put("type", "field")
                put("inboundTag", JSONArray(listOf(TUN_INBOUND_TAG)))
                put("port", DNS_PORT)
                put("outboundTag", dnsTag)
            },
        )
        // A rule of this shape that is already there is replaced, not stacked: a document
        // that is started twice must not arrive at the core with two of them.
        for (index in 0 until existing.length()) {
            val item = existing.optJSONObject(index) ?: continue
            if (isTunnelDnsRule(item)) continue
            rules.put(item)
        }
        routing.put("rules", rules)
        Log.i(TAG, "tunnel dns goes to outbound $dnsTag; ${rules.length()} routing rules")
    }

    /// Makes an observatory or balancer document work inside the tunnel.
    ///
    /// Only the documents that ask for it are touched: a plain single-node document keeps its
    /// own routing untouched. `stats` is added empty because the burst observatory writes its
    /// results there and the core refuses the document without it, and the DNS servers' own
    /// addresses get a direct rule first — the pattern Happ ships — so a resolver query cannot
    /// be routed back through the node whose health depends on it.
    private fun prepareObservatory(root: JSONObject) {
        val wantsObservatory = root.has("observatory") || root.has("burstObservatory") ||
            root.optJSONObject("routing")?.optJSONArray("balancers")?.length()?.let { it > 0 } == true
        if (!wantsObservatory) return
        if (!root.has("stats")) root.put("stats", JSONObject())

        val addresses = JsonArrayOfDnsAddresses(root)
        if (addresses.isEmpty()) return
        val outbounds = root.optJSONArray("outbounds") ?: JSONArray().also { root.put("outbounds", it) }
        var directTag: String? = null
        for (index in 0 until outbounds.length()) {
            val item = outbounds.optJSONObject(index) ?: continue
            if (!item.optString("protocol").equals("freedom", ignoreCase = true)) continue
            val tag = item.optString("tag")
            if (tag.isNotEmpty()) {
                directTag = tag
                break
            }
        }
        if (directTag == null) {
            directTag = DIRECT_OUTBOUND_TAG
            outbounds.put(
                JSONObject().apply {
                    put("tag", directTag)
                    put("protocol", "freedom")
                },
            )
        }
        val routing = root.optJSONObject("routing") ?: JSONObject().also { root.put("routing", it) }
        val existing = routing.optJSONArray("rules") ?: JSONArray()
        val rules = JSONArray()
        // First, so nothing later can claim these addresses: the resolver's own traffic is not
        // a payload to be routed, it is how this core finds out where anything is.
        rules.put(
            JSONObject().apply {
                put("type", "field")
                put("ip", JSONArray(addresses))
                put("outboundTag", directTag)
            },
        )
        for (index in 0 until existing.length()) {
            val item = existing.optJSONObject(index) ?: continue
            if (isDirectDnsRule(item)) continue
            rules.put(item)
        }
        routing.put("rules", rules)
        Log.i(TAG, "observatory document: stats added, ${addresses.size} dns address(es) go direct")
    }

    /// The literal addresses of the document's own DNS servers: a rule can only name IPs.
    private fun JsonArrayOfDnsAddresses(root: JSONObject): List<String> {
        val servers = root.optJSONObject("dns")?.optJSONArray("servers") ?: return emptyList()
        val found = mutableListOf<String>()
        for (index in 0 until servers.length()) {
            val raw = when (val item = servers.opt(index)) {
                is String -> item
                is JSONObject -> item.optString("address")
                else -> ""
            }
            // `8.8.8.8`, `8.8.8.8:53`, `https://1.1.1.1/dns-query`: take the host and keep it
            // only when it is an address, never a name.
            val host = raw.removePrefix("https://").removePrefix("tls://")
                .removePrefix("quic://").substringBefore('/').substringBefore(':')
            if (host.count { it == '.' } == 3 && host.all { it.isDigit() || it == '.' }) {
                found.add(host)
            }
        }
        return found
    }

    /// The direct rule this class writes for the resolver's own addresses.
    private fun isDirectDnsRule(rule: JSONObject): Boolean {
        if (!rule.optString("type").equals("field", ignoreCase = true)) return false
        if (rule.optJSONArray("ip") == null) return false
        return rule.optString("outboundTag") == DIRECT_OUTBOUND_TAG ||
            rule.optJSONArray("inboundTag") == null && rule.optJSONArray("domain") == null
    }

    /// The rule this class writes, whichever tag an older version gave it.
    private fun isTunnelDnsRule(rule: JSONObject): Boolean {
        if (!rule.optString("type").equals("field", ignoreCase = true)) return false
        val inbound = rule.optJSONArray("inboundTag") ?: return false
        if (inbound.length() != 1 || inbound.optString(0) != TUN_INBOUND_TAG) return false
        return rule.optString("port") == DNS_PORT.toString()
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
    /// The service publishes once per VPN start, so a fresh publish always wins. The cached
    /// descriptor is what a restart after a tap uses, since the interface behind it did not
    /// change — but only while it is still open: a VPN torn down and established again closes
    /// the old descriptor, and its number then belongs to whichever file the process opened
    /// next, which is how a restart used to hand the core `inappropriate ioctl for device`.
    /// A dead cache is dropped and the wait below is for the tunnel that replaced it.
    private fun tunForChild(): XrayTun? {
        XrayTunHolder.take()?.takeIf { it.live }?.let { tun ->
            cachedTun = tun
            return tun
        }
        cachedTun?.let { cached ->
            if (cached.live) return cached
            cachedTun = null
        }
        return XrayTunHolder.await(TUN_WAIT_MS)?.takeIf { it.live }?.also { cachedTun = it }
    }

    /// Waits for the core's own line that says the tunnel is being read.
    ///
    /// The core runs in this process, so there is no output stream to drain and no exit code
    /// to read. What it writes to the log the document names is the only evidence: the tun
    /// reader says it started, or an `[Error]` line says it never will. Both end the wait —
    /// one as the acknowledgement, one as the failure, each with the core's own words.
    private fun awaitAck(token: Long, fd: Int, logFile: File, epoch: Long): Map<String, Any> {
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
                // The core writes to the file the document names and nowhere else, and the
                // shipped build is not debuggable: `run-as` refuses it, so the file cannot be
                // read on the device that matters. Every line is repeated here in the core's
                // own words, which is what makes a refusal, or the reader's start line,
                // evidence on the device instead of a claim about it.
                Log.i(TAG, "core: $lastLine")
                // The reader's start line is the proof, in either spelling the core prints.
                // A failure line answers the start now, not at the deadline: a refused
                // document would otherwise sit out the whole timeout saying nothing.
                if (ACK_MARKERS.any { lastLine.contains(it, ignoreCase = true) }) {
                    Log.i(TAG, "xray is reading the tunnel on fd $fd (epoch $epoch)")
                    return mapOf(
                        "ok" to true,
                        "message" to "tunnel on fd $fd",
                        "epoch" to epoch,
                    )
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

        /// How long a coordinator entry waits for the core's own answer. Above the ack's own
        /// deadline plus the tunnel wait, so a slow start reports the core's words rather
        /// than this timeout.
        private const val START_WAIT_MS = 45_000L

        /// `XrayStop` returns when the core has let go of its tunnels; a stop that never
        /// returns is a fact the caller has to hear instead of waiting forever.
        private const val STOP_WAIT_MS = 30_000L

        /// A sweep of a whole subscription takes seconds; the cap is the Incy one (120 s) plus
        /// room for the answer to travel, after which the caller is told it failed rather than
        /// left waiting on a wedged core.
        private const val MEASURE_WAIT_MS = 130_000L

        /// How often the log is read, and how finely a sleep is cut so a stop does not wait
        /// out a whole interval before the start gives up.
        private const val POLL_MS = 200L
        private const val POLL_SLICE_MS = 50L

        /// How long the plugin waits for the service to publish the tunnel it just made.
        private const val TUN_WAIT_MS = 8_000L

        /// The document the core is started from, and the log this start reads.
        private const val CONFIG_NAME = "xray-tun.json"

        /// The direct outbound this class adds when a document needs one and has none.
        private const val DIRECT_OUTBOUND_TAG = "portal-direct"

        /// The measurement core's own document: a different file, so a sweep can never be
        /// mistaken for the tunnel's configuration or overwrite it.
        private const val MEASURE_CONFIG_NAME = "xray-measure.json"
        private const val LOG_NAME = "xray.log"

        /// The directory the geodata files are installed into, and the core's variable for it.
        private const val GEODATA_DIR = "xray-assets"
        private const val ASSET_ENV = "XRAY_LOCATION_ASSET"

        /// What a start answers when the build carries no usable core.
        private const val UNAVAILABLE = "xray is not available in this build"
        private const val NO_ENTRY_POINTS = "libxray.so is missing its JNI entry points"

        /// The line the core prints when its tunnel is actually up: `<name> up`, written by
        /// proxy/tun/handler.go only after the stack and the inbound started. The Android
        /// reader's `read Android Tun Fd` line looks like proof and is not — it is written
        /// before the descriptor is validated — so a start waits for this one, and a core that
        /// never prints it never had a working tunnel.
        private val ACK_MARKERS = listOf("$TUN_NAME up")

        /// Info, not the panel's level: without it the acknowledgement line is filtered out.
        private const val ACK_LOG_LEVEL = "info"

        private const val TUN_NAME = "portal0"
        private const val TUN_INBOUND_TAG = "tun-in"

        /// The outbound that answers the tunnel's own DNS queries, and the port they arrive on.
        private const val DNS_OUTBOUND_TAG = "portal-dns"
        private const val DNS_PORT = 53

        /// Used only when the document has no resolver of its own to query.
        private const val FALLBACK_DNS_1 = "1.1.1.1"
        private const val FALLBACK_DNS_2 = "8.8.8.8"

        val CHANNEL = "${Components.PACKAGE_NAME}/xray"
    }
}
