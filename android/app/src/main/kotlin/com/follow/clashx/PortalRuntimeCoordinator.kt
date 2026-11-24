package com.follow.clashx

import com.follow.clashx.common.GlobalState
import com.follow.clashx.plugins.ServicePlugin
import com.follow.clashx.plugins.XrayPlugin
import java.io.File
import com.follow.clashx.common.PortalOwner
import com.follow.clashx.common.PortalRuntime
import com.follow.clashx.common.PortalRuntimeState
import com.follow.clashx.common.XrayTunHolder
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/// What the child answered for one start: its own words, and the tunnel epoch it read.
data class PortalChildStart(
    val ok: Boolean,
    val cancelled: Boolean = false,
    val reason: String = "",
    val epoch: Long = 0L,
)

/// What the child answered for one stop. `ok` is only ever true once `XrayStop` returned.
data class PortalChildStop(
    val ok: Boolean,
    val reason: String = "",
)

/**
 * The plugin's half of a transaction, as the coordinator needs it: start and stop that only
 * return when the core itself has answered, and the flag it keeps.
 *
 * The coordinator never touches the core directly: the plugin owns the JNI calls and the
 * executor they run on, and this is the narrow face it turns towards the one lock.
 */
interface PortalChildGateway {
    fun start(config: String): PortalChildStart

    fun stop(): PortalChildStop

    val running: Boolean

    /** The core's own last line, for a failure the coordinator has to report. */
    val coreLine: String
}

/// The answer of one entry: what happened, and the record it left behind.
data class PortalOutcome(
    val ok: Boolean,
    val cancelled: Boolean = false,
    val reason: String = "",
    val runtime: PortalRuntime = PortalRuntimeState.current(),
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "ok" to ok,
        "cancelled" to cancelled,
        "message" to reason,
        "state" to runtime.toMap(),
    )
}

/**
 * The one gate every entry to the tunnel goes through.
 *
 * The power button, a row tap, Quick Settings, Always-on, a revoke and a restart all ended
 * up here before, in three different places: a Dart flag around the mode switch, the
 * service's own mutex around `ServiceController.start`, and a row tap that called Xray
 * directly. Each was correct about its own little step and none of them knew about the
 * others, which is how two readers of one interface, a start cancelled by its own stop and
 * an `Already closed` descriptor all reached the device.
 *
 * Now there is one entry and one mutex, and the lock order is fixed and one-directional:
 *
 *     coordinator → transitionLock (ServiceStateMachine) → ServiceController.lock → tunLock
 *
 * Every path below follows it and none of them takes it backwards. A revoke is the one
 * exception, and it is not a lock but a fence: it mints a new generation without waiting,
 * so a transaction that is holding the mutex cannot publish its `Active` over a tunnel the
 * system has already taken away.
 *
 * `Active` is published only after the owner has answered for itself — the child's
 * `portal0 up`, or the engine's service and listener — with the generation and the tunnel
 * epoch it was confirmed on.
 */
object PortalRuntimeCoordinator {
    private const val TAG = "PortalRuntime"

    /// The last document a run actually started on, for a start with no Flutter engine.
    private const val SAVED_DOCUMENT = "portal-last-node.json"

    // The tags the child document marks its nodes with; they mirror `portal_document.dart`.
    private const val NODE_TAG_PREFIX = "node:"
    private const val SELECTED_TAG = "portal-selected"

    private val mutex = Mutex()

    @Volatile
    private var child: PortalChildGateway? = null

    /// Builds the child's document on demand, for an entry that does not carry one.
    ///
    /// Quick Settings and Always-on ask for a run without a Flutter call stack; the document
    /// is the profile's, and only Dart can build it. This is how the one entry gets it, and
    /// it is awaited inside the mutex so the profile it was built from is the one the
    /// transaction confirms.
    @Volatile
    private var configSource: (suspend () -> String?)? = null

    fun attachChild(gateway: PortalChildGateway) {
        child = gateway
    }

    fun detachChild(gateway: PortalChildGateway) {
        if (child === gateway) child = null
    }

    fun provideChildConfig(source: (suspend () -> String?)?) {
        configSource = source
    }

    /// The node document the previous run used, kept on disk for a start with no Flutter.
    ///
    /// The tile can be tapped while the app is not running, and at that moment there is no Dart
    /// side to build a document — `configSource` is a call into a Flutter engine that does not
    /// exist. 0.01a answered that by starting from the saved preferences, and that is what makes
    /// the tile work with the app thrown out of memory. This is the same idea: the last document
    /// a run actually started on, written next to the core's own files and replayed when no
    /// builder answers.
    private fun savedDocumentFile(): File =
        File(GlobalState.application.filesDir, SAVED_DOCUMENT)

    fun rememberDocument(document: String) {
        runCatching { savedDocumentFile().writeText(document, Charsets.UTF_8) }
            .onFailure { GlobalState.log("$TAG cannot save the node document: ${it.message}") }
    }

    fun savedDocument(): String? = runCatching {
        val file = savedDocumentFile()
        if (!file.exists()) return null
        file.readText(Charsets.UTF_8).takeIf { it.isNotBlank() }
    }.getOrNull()

    /** The owner the shared state asks for: the mode, as the app last wrote it. */
    fun desiredOwner(): PortalOwner {
        val options = runCatching { AndroidServiceStateHost.loadSharedState().vpnOptions }.getOrNull()
        return if (options?.xrayTun == true) PortalOwner.Xray else PortalOwner.Mihomo
    }

    /// Quick Settings' start: the owner the mode names, and the document Dart builds — or, with
    /// no engine attached, the document the last run started on.
    suspend fun openDesired(): PortalOutcome = open(desiredOwner())

    fun status(): Map<String, Any?> = PortalRuntimeState.current().toMap() + mapOf(
        "engine" to (ServiceController.runtime != null),
        "child" to (child?.running == true),
        "childLine" to (child?.coreLine.orEmpty()),
    )

    /** Opens the tunnel for [owner], or moves it there from whoever holds it now. */
    suspend fun open(
        owner: PortalOwner,
        config: String? = null,
        why: String = "app",
    ): PortalOutcome = mutex.withLock {
        GlobalState.log("$TAG entry=open owner=${owner.label} why=$why config=${config != null}")
        guarded { openLocked(owner, config, why) }
    }

    /** Closes the tunnel: the child first, then the service, and the record follows. */
    suspend fun close(reason: String = "stop"): PortalOutcome = mutex.withLock {
        GlobalState.log("$TAG entry=close reason=$reason")
        guarded { closeLocked(reason) }
    }

    suspend fun restart(config: String? = null): PortalOutcome = mutex.withLock {
        GlobalState.log("$TAG entry=restart")
        guarded {
            val owner = desiredOwner()
            val closed = closeLocked("restart")
            if (!closed.ok) closed else openLocked(owner, config, "restart")
        }
    }

    /** A row tap: the same owner, a new document, under the same lock. */
    suspend fun startChild(config: String): PortalOutcome = mutex.withLock {
        GlobalState.log("$TAG entry=startChild")
        guarded {
            val seen = PortalRuntimeState.current()
            if (seen is PortalRuntime.Active && seen.owner == PortalOwner.Xray) {
                // The tunnel stays: only the core reading it is replaced, and the same
                // generation moves through Starting to Active so a late answer from the
                // core that was just replaced cannot claim the record.
                val generation = PortalRuntimeState.nextGeneration()
                PortalRuntimeState.publish(PortalRuntime.Starting(generation, PortalOwner.Xray), "row")
                startChildLocked(generation, config, "row")
            } else {
                openLocked(PortalOwner.Xray, config, "row")
            }
        }
    }

    /** Quick Settings and the launcher's quick action. */
    suspend fun toggle(): PortalOutcome = mutex.withLock {
        val running = PortalRuntimeState.current().isLive || ServiceController.runtime != null
        GlobalState.log("$TAG entry=toggle running=$running")
        guarded {
            when {
                running -> closeLocked("quick-settings")
                else -> openLocked(desiredOwner(), null, "quick-settings")
            }
        }
    }

    /// The notification's bolt: the same sweep the working screen's bolt runs — every node of
    /// the live group, one delay test each, so a url-test group re-picks its fastest node and
    /// a selector group refreshes the whole list. Sent straight to the engine with no Flutter
    /// round-trip.
    suspend fun ping(): PortalOutcome = mutex.withLock {
        val state = AndroidServiceStateHost.loadSharedState()
        val testUrl = state.setupParams?.testUrl ?: "https://www.gstatic.com/generate_204"
        val servers = state.pingServers
        GlobalState.log("$TAG entry=ping servers=${servers.size} testUrl=$testUrl")
        if (servers.isEmpty()) {
            return@withLock PortalOutcome(ok = false, reason = "no servers to ping")
        }
        var ok = true
        var lastError = "ping sent"
        for (server in servers) {
            val escaped = server.replace("\\", "\\\\").replace("\"", "\\\"")
            val call =
                """{"method":"asyncTestDelay","arguments":{"proxy-name":"$escaped","timeout":5000,"test-url":"$testUrl"}}"""
            val sent = ServiceController.invokeMethod(call) { }
            if (sent.isFailure) {
                ok = false
                lastError = sent.exceptionOrNull()?.message ?: "ping failed"
            }
            // The core's delay test is async, but firing every node at once floods its dial
            // pool and the re-pick sometimes never lands. One short beat per node keeps the
            // sweep a sweep instead of a burst.
            delay(40)
        }
        PortalOutcome(ok = ok, reason = lastError)
    }

    /// The shade's "next server" in the simple portal: the saved document holds every node with
    /// the selected one tagged `portal-selected`, so cycling rewrites that one outbound to the
    /// next node and starts the child on it — no Flutter, the same way the bolt pings.
    suspend fun nextServer(): PortalOutcome = mutex.withLock {
        GlobalState.log("$TAG entry=nextServer")
        guarded {
            val document = savedDocument()
            if (document == null) {
                GlobalState.log("$TAG nextServer: no saved document to cycle")
                return@guarded PortalOutcome(ok = false, reason = "no saved document to cycle")
            }
            val cycled = cycleSelectedNode(document)
            if (cycled == null) {
                GlobalState.log("$TAG nextServer: nothing to cycle (document ${document.length} chars)")
                return@guarded PortalOutcome(ok = false, reason = "nothing to cycle")
            }
            val owner = desiredOwner()
            val closed = closeLocked("next-server")
            val outcome = if (!closed.ok) closed else openLocked(owner, cycled.first, "next-server")
            // The app's pick must follow the shade's cycle, or the notification keeps the old name.
            ServicePlugin.notifyNextServerDone(cycled.second)
            outcome
            }
            }

    /// Rewrites the document's `portal-selected` outbound to the next node (wrapping after the
    /// last) and returns the new document, or null when there is no next node to switch to.
    private fun cycleSelectedNode(document: String): Pair<String, String>? {
        val root = runCatching { JsonParser.parseString(document).asJsonObject }.getOrNull()
            ?: return null
        val outbounds = root.getAsJsonArray("outbounds") ?: return null
        val nodes = mutableListOf<JsonObject>()
        var selectedIndex = -1
        var lastNodeIndex = -1
        for (element in outbounds) {
            val item = element as? JsonObject ?: continue
            val tag = item.get("tag")?.asString ?: continue
            when {
                tag.startsWith(NODE_TAG_PREFIX) -> {
                    nodes.add(item)
                    lastNodeIndex = nodes.size - 1
                }

                tag == SELECTED_TAG -> selectedIndex = lastNodeIndex
            }
        }
        // Two nodes are the minimum for a cycle; one node (or no selection) has no next.
        if (nodes.size < 2 || selectedIndex < 0) return null
        val nextNode = nodes[(selectedIndex + 1) % nodes.size]
        // The name the shade and the app both read: the node's tag says the name, not a position,
        // and a duplicate name carries a `#<n>` suffix that is not part of the pick.
        val nextTag = nextNode.get("tag")?.asString ?: ""
        var nextName = nextTag.removePrefix(NODE_TAG_PREFIX)
        val repeat = nextName.lastIndexOf('#')
        if (repeat > 0 && nextName.substring(repeat + 1).toIntOrNull() != null) {
            nextName = nextName.substring(0, repeat)
        }
        val selectedCopy = nextNode.deepCopy()
        selectedCopy.addProperty("tag", SELECTED_TAG)
        // The selected handle must sit right after the node it names: only then does the next
        // cycle read the new position. Replacing the old handle in place left it anchored to the
        // previous node, so every press cycled to the same server.
        val rebuilt = JsonArray()
        for (element in outbounds) {
            val item = element as? JsonObject ?: continue
            val tag = item.get("tag")?.asString ?: ""
            if (tag == SELECTED_TAG) continue
            rebuilt.add(item)
            if (tag == nextTag) {
                rebuilt.add(selectedCopy)
            }
        }
        root.add("outbounds", rebuilt)
        return Pair(root.toString(), nextName)
    }

    // Any throw is this transaction's own failure; it must not leave a Starting record that
    // nothing will ever finish, and it must not escape to a caller that only reads `ok`.
    private suspend fun guarded(block: suspend () -> PortalOutcome): PortalOutcome = try {
        block()
    } catch (error: kotlinx.coroutines.CancellationException) {
        GlobalState.log("$TAG transaction cancelled: $error")
        throw error
    } catch (error: Exception) {
        val generation = PortalRuntimeState.nextGeneration()
        val reason = error.message ?: error.toString()
        GlobalState.log("$TAG transaction failed: $reason")
        PortalRuntimeState.publish(PortalRuntime.Failed(generation, reason), "failed")
        PortalOutcome(ok = false, reason = reason)
    }

    private suspend fun openLocked(
        owner: PortalOwner,
        config: String?,
        why: String,
    ): PortalOutcome {
        val seen = PortalRuntimeState.current()
        // The same owner, and nothing new to hand it: the portal is already what was asked.
        if (seen is PortalRuntime.Active && seen.owner == owner &&
            (owner == PortalOwner.Mihomo || config == null)
        ) {
            GlobalState.log("$TAG phase=Active owner=${owner.label} result=already-active")
            return PortalOutcome(ok = true, runtime = seen)
        }
        val generation = PortalRuntimeState.nextGeneration()
        PortalRuntimeState.publish(PortalRuntime.Starting(generation, owner), why)

        // 1. Whoever holds the tunnel lets go first, and only after saying so.
        releaseLocked(generation, seen, why)?.let { return it }
        if (!stillCurrent(generation)) return stale(generation, "open")

        // 2. The service, in the mode Dart has already written into the shared state.
        GlobalState.log("$TAG phase=Starting owner=${owner.label} step=service")
        val epochBefore = PortalRuntimeState.currentFdEpoch()
        if (!startService(generation, owner)) {
            return failed(generation, "the service did not start for ${owner.label}")
        }
        // The service chose its own reader when it established the tunnel, from the options
        // it had. A child's tunnel published for an engine start is a mismatch no answer
        // can paper over: nothing of the engine would be reading it, and calling that
        // `Active owner=Mihomo` is exactly the false record this patch exists to remove.
        if (owner == PortalOwner.Mihomo && XrayTunHolder.currentEpoch() > epochBefore) {
            // The service established the child's tunnel: the options it started from still named
            // the child as the reader, left over from the simple portal. A start with the wrong
            // reader is a start that can be redone — not a portal that has to close — so the
            // service is stopped, the reader is pointed at the engine and the start is asked once
            // more. A second mismatch is a real refusal and stays one.
            GlobalState.log(
                "$TAG generation=$generation the service built the child's tunnel, " +
                    "restarting it for the engine",
            )
            stopService()
            ServiceState.pointTunnelAt(child = false)
            val retryEpoch = PortalRuntimeState.currentFdEpoch()
            if (!startService(generation, owner)) {
                return failed(generation, "the service did not start for ${owner.label}")
            }
            if (XrayTunHolder.currentEpoch() > retryEpoch) {
                stopService()
                return failed(
                    generation,
                    "the service published a child tunnel while the engine was asked for one",
                )
            }
        }
        if (!stillCurrent(generation)) {
            runCatching { ServiceState.requestStop() }
            return stale(generation, "service start")
        }

        // 3. The child, when the tunnel is the child's: it alone can acknowledge reading it.
        if (owner == PortalOwner.Xray) {
            return startChildLocked(generation, config, why)
        }
        // 4. The engine answered by taking the descriptor in `Core.startTun`; publish it —
        // but only when there is a runtime to have taken it. A service that came up and then
        // carried nothing is not `Active`, and a green tile over a dead tunnel is the one lie
        // this record cannot afford.
        if (ServiceController.runtime == null) {
            stopService()
            return failed(generation, "the engine did not take the tunnel")
        }
        val epoch = PortalRuntimeState.currentFdEpoch()
        PortalRuntimeState.publish(PortalRuntime.Active(generation, PortalOwner.Mihomo, epoch), why)
        GlobalState.log("$TAG phase=Active owner=Mihomo generation=$generation fdEpoch=$epoch result=ok")
        return PortalOutcome(ok = true, runtime = PortalRuntimeState.current())
    }

    private suspend fun startChildLocked(
        generation: Long,
        config: String?,
        why: String,
    ): PortalOutcome {
        // The core does not need Flutter to exist: the process keeps one instance, created
        // headless by whoever asks first (the shade's tile can arrive before any engine) and
        // adopted by the engine when the app opens. This is the same object either way, so the
        // tile and the app's button hold the same tunnel, not two copies of one.
        val gateway = child ?: runCatching {
            if (!XrayPlugin.available()) return@runCatching null
            XrayPlugin.obtain().also { attachChild(it) }
        }.getOrNull()
            ?: return failed(generation, "this build has no portal core for the tunnel")
        // A caller that carries a document is the app itself; one that does not is the tile, and
        // the builder it would ask may be a Flutter engine that is not running. The last document
        // a run started on is the honest answer there — it is the node the owner last used.
        val document = config
            ?: configSource?.invoke()?.takeIf { it.isNotBlank() }
            ?: savedDocument()
        if (document.isNullOrBlank()) {
            closeServiceAfterFailure()
            return failed(generation, "no node document to start the portal core on")
        }
        if (!stillCurrent(generation)) {
            closeServiceAfterFailure()
            return stale(generation, "child start")
        }
        // The service publishes the child's tunnel when it establishes, and a service already
        // running for the engine never establishes a second one — the switch then found an empty
        // slot and reported "the portal has no open tunnel" over a VPN that was perfectly up.
        // With nothing in hand the service is restarted with the child as its reader, which is
        // what publishes a tunnel at all.
        ServiceState.pointTunnelAt(child = true)
        if (XrayTunHolder.peek() == null) {
            runCatching { ServiceState.requestStop().await() }
                .onFailure { GlobalState.log("$TAG the service did not stop: ${it.message}") }
            if (!startService(generation, PortalOwner.Xray)) {
                closeServiceAfterFailure()
                return failed(generation, "the service did not start for the portal core")
            }
        }
        GlobalState.log("$TAG phase=Starting owner=Xray step=child generation=$generation")
        // Remembered before the start, not after: a core that refuses still names the document a
        // later no-Flutter start would have to try, and a start that fails is not a reason to
        // forget which node the owner picked.
        rememberDocument(document)
        val started = gateway.start(document)
        if (!started.ok) {
            // A core that refused has already let the tunnel go; the service must not stay
            // up over an interface nothing reads.
            closeServiceAfterFailure()
            if (started.cancelled) {
                GlobalState.log("$TAG phase=Failed owner=Xray generation=$generation cancelled")
                return PortalOutcome(ok = false, cancelled = true, reason = started.reason)
            }
            return failed(generation, started.reason)
        }
        if (!stillCurrent(generation)) {
            gateway.stop()
            closeServiceAfterFailure()
            return stale(generation, "child acknowledgement")
        }
        PortalRuntimeState.publish(
            PortalRuntime.Active(generation, PortalOwner.Xray, started.epoch),
            why,
        )
        GlobalState.log(
            "$TAG phase=Active owner=Xray generation=$generation fdEpoch=${started.epoch} result=ok",
        )
        return PortalOutcome(ok = true, runtime = PortalRuntimeState.current())
    }

    /** Stops whoever holds the tunnel. `null` when there was nobody to stop. */
    private suspend fun releaseLocked(
        generation: Long,
        seen: PortalRuntime,
        why: String,
    ): PortalOutcome? {
        val previous = seen.owner
        if (previous == null || (!seen.isLive && seen !is PortalRuntime.Failed)) return null
        PortalRuntimeState.publish(PortalRuntime.Stopping(generation, previous), why)
        GlobalState.log("$TAG phase=Stopping owner=${previous.label} generation=$generation")
        if (previous == PortalOwner.Xray || child?.running == true) {
            val stopped = child?.stop() ?: PortalChildStop(ok = true)
            if (!stopped.ok) {
                return failed(generation, "the portal core did not stop: ${stopped.reason}")
            }
            GlobalState.log("$TAG phase=Stopping owner=Xray generation=$generation xraystop=ok")
        }
        if (ServiceController.runtime != null && !stopService()) {
            return failed(generation, "the service did not stop")
        }
        return null
    }

    private suspend fun closeLocked(reason: String): PortalOutcome {
        val seen = PortalRuntimeState.current()
        val generation = PortalRuntimeState.nextGeneration()
        if (seen.isLive && seen.owner != null) {
            PortalRuntimeState.publish(PortalRuntime.Stopping(generation, seen.owner!!), reason)
            GlobalState.log(
                "$TAG phase=Stopping owner=${seen.owner!!.label} generation=$generation reason=$reason",
            )
        }
        var ok = true
        var problem = ""
        if (seen.owner == PortalOwner.Xray || child?.running == true) {
            val stopped = child?.stop() ?: PortalChildStop(ok = true)
            if (!stopped.ok) {
                ok = false
                problem = "the portal core did not stop: ${stopped.reason}"
            }
        }
        if (ServiceController.runtime != null && !stopService()) {
            ok = false
            if (problem.isEmpty()) problem = "the service did not stop"
        }
        if (!ok) return failed(generation, problem)
        PortalRuntimeState.publish(PortalRuntime.Off(generation), reason)
        GlobalState.log("$TAG phase=Off generation=$generation result=ok reason=$reason")
        return PortalOutcome(ok = true, runtime = PortalRuntimeState.current())
    }

    private suspend fun startService(generation: Long, owner: PortalOwner): Boolean {
        // The service reads its options from the shared state that the app writes and the
        // machine holds in memory. A start that did not come from Flutter — the shade's tile,
        // a shortcut, a boot — has nothing in memory yet, and without this line the request is
        // refused as if the app had no profile. The same state is what the 0.01a tile path
        // loaded before asking; here it is loaded for every entry, once, before the ask.
        // Only a start with nothing in hand needs the file: with Flutter attached the machine
        // already holds the options Dart just wrote, and loading over them would bring back the
        // mode the disk had a moment ago — the service would then build the other core's tunnel
        // and the engine start would be refused as a mismatch.
        if (!ServiceState.hasSharedState) {
            runCatching { ServiceState.syncSharedState(AndroidServiceStateHost.loadSharedState()) }
                .onFailure { GlobalState.log("$TAG cannot load the shared state: ${it.message}") }
        }
        // The tunnel's reader is the owner being started — after the load, never before it: the
        // file may name the other core, and pointing first only to be overwritten by the load is
        // how the service came to establish the child's tunnel under an engine start.
        ServiceState.pointTunnelAt(child = owner != PortalOwner.Mihomo)
        GlobalState.log(
            "$TAG generation=$generation tunnel reader=${if (owner == PortalOwner.Mihomo) "engine" else "child"}",
        )
        // The engine must be configured before a tunnel is handed to it: its config lives in
        // memory and is normally written by Dart, which a start from the shade does not have.
        // Without this the service comes up carrying nothing, and calling that `Active` is the
        // false record this whole path exists to avoid.
        if (owner == PortalOwner.Mihomo && ServiceController.runtime == null) {
            val ready = runCatching { ServiceState.prepareCore() }.getOrDefault(false)
            GlobalState.log("$TAG generation=$generation engine prepared=$ready")
            if (!ready) return false
        }
        val answered = ServiceState.requestStart().await()
        GlobalState.log(
            "$TAG generation=$generation step=service start=$answered " +
                "engine=${ServiceController.runtime != null}",
        )
        return answered
    }

    // The stop is the service's own answer: what it returns is whether the transition that
    // was asked for is still the newest one, and the record follows the tunnel being gone.
    private suspend fun stopService(): Boolean {
        val answered = ServiceState.requestStop().await()
        GlobalState.log("$TAG step=service stop=$answered engine-off=${ServiceController.runtime == null}")
        return answered
    }

    private suspend fun closeServiceAfterFailure() {
        runCatching { stopService() }
            .onFailure { GlobalState.log("$TAG unable to close the service after a failure: $it") }
    }

    private fun stillCurrent(generation: Long): Boolean = PortalRuntimeState.isCurrent(generation)

    private fun stale(generation: Long, step: String): PortalOutcome {
        GlobalState.log(
            "$TAG generation=$generation step=$step result=stale " +
                "(now ${PortalRuntimeState.current().describe()})",
        )
        return PortalOutcome(
            ok = false,
            cancelled = true,
            reason = "a newer command took the portal during $step",
        )
    }

    private fun failed(generation: Long, reason: String): PortalOutcome {
        PortalRuntimeState.publish(PortalRuntime.Failed(generation, reason), "failed")
        GlobalState.log("$TAG generation=$generation phase=Failed reason=$reason")
        return PortalOutcome(ok = false, reason = reason)
    }
}
