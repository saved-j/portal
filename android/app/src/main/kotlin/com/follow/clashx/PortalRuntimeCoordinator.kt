package com.follow.clashx

import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalOwner
import com.follow.clashx.common.PortalRuntime
import com.follow.clashx.common.PortalRuntimeState
import com.follow.clashx.common.XrayTunHolder
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

    /** The owner the shared state asks for: the mode, as the app last wrote it. */
    fun desiredOwner(): PortalOwner {
        val options = runCatching { AndroidServiceStateHost.loadSharedState().vpnOptions }.getOrNull()
        return if (options?.xrayTun == true) PortalOwner.Xray else PortalOwner.Mihomo
    }

    /** Quick Settings' start: the owner the mode names, and the document Dart builds. */
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
        if (!startService(generation)) {
            return failed(generation, "the service did not start for ${owner.label}")
        }
        // The service chose its own reader when it established the tunnel, from the options
        // it had. A child's tunnel published for an engine start is a mismatch no answer
        // can paper over: nothing of the engine would be reading it, and calling that
        // `Active owner=Mihomo` is exactly the false record this patch exists to remove.
        if (owner == PortalOwner.Mihomo && XrayTunHolder.currentEpoch() > epochBefore) {
            stopService()
            return failed(
                generation,
                "the service published a child tunnel while the engine was asked for one",
            )
        }
        if (!stillCurrent(generation)) {
            runCatching { ServiceState.requestStop() }
            return stale(generation, "service start")
        }

        // 3. The child, when the tunnel is the child's: it alone can acknowledge reading it.
        if (owner == PortalOwner.Xray) {
            return startChildLocked(generation, config, why)
        }
        // 4. The engine answered by taking the descriptor in `Core.startTun`; publish it.
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
        val gateway = child
            ?: return failed(generation, "this build has no portal core for the tunnel")
        val document = config ?: configSource?.invoke()
        if (document.isNullOrBlank()) {
            closeServiceAfterFailure()
            return failed(generation, "no node document to start the portal core on")
        }
        if (!stillCurrent(generation)) {
            closeServiceAfterFailure()
            return stale(generation, "child start")
        }
        GlobalState.log("$TAG phase=Starting owner=Xray step=child generation=$generation")
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

    private suspend fun startService(generation: Long): Boolean {
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
