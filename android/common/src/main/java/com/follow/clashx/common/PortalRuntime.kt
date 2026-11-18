package com.follow.clashx.common

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Who reads the one tunnel the VpnService established.
 *
 * `Mode.global` only says which owner the app *wants* next; this enum is the owner a
 * generation actually has. The two are never the same question: a mode change while the
 * portal is closed changes only the wish, and a wish that is being carried out is not yet
 * a fact — that is what [PortalRuntime.Starting] and [PortalRuntime.Active] separate.
 */
enum class PortalOwner(val label: String) {
    Mihomo("Mihomo"),
    Xray("Xray"),
    ;

    companion object {
        fun of(value: String?): PortalOwner? = entries.firstOrNull {
            it.label.equals(value, ignoreCase = true) || it.name.equals(value, ignoreCase = true)
        }
    }
}

/**
 * The process-wide record of the tunnel's owner, at one generation.
 *
 * Exactly one of these describes the process at any moment. A generation moves on every
 * open, close, switch and restart, and a late answer from an older generation — a stop that
 * finally returned, a start that acknowledged after the user closed the portal — is
 * recognised by its number and cannot publish itself over the newer state. That is the
 * difference between a portal that *is* owned and one that is *believed* to be owned: the
 * plugin used to report `running`, the service `xrayTunActive`, and neither said which of
 * the two was reading the descriptor now.
 *
 * [Active] is only ever published after the owner's own acknowledgement — `portal0 up` from
 * the child's log, or a started service and its engine listener for the engine. Anything
 * short of that is [Failed] with the owner's own words, and the portal is closed rather than
 * reported open over a tunnel nothing reads.
 */
sealed class PortalRuntime {
    abstract val generation: Long

    /** The owner this state is about, if any: `Off` and a failed start name none. */
    open val owner: PortalOwner? get() = null

    /** The tunnel epoch this state was confirmed on; `0` before an establish. */
    open val fdEpoch: Long get() = 0L

    abstract val phase: String

    /** Whether an owner is holding the tunnel right now. */
    open val isLive: Boolean get() = false

    data class Off(override val generation: Long = 0L) : PortalRuntime() {
        override val phase: String get() = "Off"
    }

    data class Starting(
        override val generation: Long,
        override val owner: PortalOwner,
    ) : PortalRuntime() {
        override val phase: String get() = "Starting"
        override val isLive: Boolean get() = true
    }

    data class Active(
        override val generation: Long,
        override val owner: PortalOwner,
        override val fdEpoch: Long,
    ) : PortalRuntime() {
        override val phase: String get() = "Active"
        override val isLive: Boolean get() = true
    }

    data class Stopping(
        override val generation: Long,
        override val owner: PortalOwner,
    ) : PortalRuntime() {
        override val phase: String get() = "Stopping"
        override val isLive: Boolean get() = true
    }

    data class Failed(
        override val generation: Long,
        val reason: String,
    ) : PortalRuntime() {
        override val phase: String get() = "Failed"
    }

    /** One line: the record, in the log and on the channel, spelled the same way. */
    fun describe(): String = buildString {
        append("generation=").append(generation)
        append(" phase=").append(phase)
        owner?.let { append(" owner=").append(it.label) }
        if (fdEpoch > 0) append(" fdEpoch=").append(fdEpoch)
        if (this@PortalRuntime is Failed) append(" reason=").append(reason)
    }

    fun toMap(): Map<String, Any?> = mapOf(
        "generation" to generation,
        "phase" to phase,
        "owner" to owner?.label,
        "fdEpoch" to fdEpoch,
        "reason" to (this as? Failed)?.reason.orEmpty(),
        "running" to (this is Active),
    )

    companion object {
        val initial: PortalRuntime = Off(0L)
    }
}

/**
 * The one place the record is written, and the one place a number is minted.
 *
 * [publish] refuses anything older than what it already holds, so a transaction that was
 * overtaken — a revoke, a newer open, a close — cannot put its answer back on top. Closing
 * is the exception only in appearance: a revoke mints a new generation first, which is why
 * the late `Active` loses.
 */
object PortalRuntimeState {
    private const val TAG = "PortalRuntime"

    private val state = AtomicReference(PortalRuntime.initial)
    private val generationSeq = AtomicLong(0)
    private val fdEpochSeq = AtomicLong(0)

    /// Called for every state that is accepted, with the state it replaced.
    ///
    /// The record does not know who reads it, and it does not pick one reader: the telemetry
    /// file, the Flutter bridge and anything else that must follow the tunnel all attach here.
    /// A single slot used to hold this, so attaching the bridge silently displaced the file —
    /// the transitions log would have gone quiet the moment the app was alive to listen.
    private val observers = CopyOnWriteArrayList<(PortalRuntime, PortalRuntime, String) -> Unit>()

    /// Adds a reader; returns the call that removes it again.
    fun addObserver(observer: (PortalRuntime, PortalRuntime, String) -> Unit): () -> Unit {
        observers.add(observer)
        return { observers.remove(observer) }
    }

    /// Kept for the one caller that predates the list: it now adds a reader like any other.
    var onPublish: ((PortalRuntime, PortalRuntime, String) -> Unit)? = null
        set(value) {
            field = value
            value?.let { observers.add(it) }
        }

    fun current(): PortalRuntime = state.get()

    /** A number no earlier step holds; every entry takes one before it changes anything. */
    fun nextGeneration(): Long = generationSeq.incrementAndGet()

    /** A number for one established tunnel; it moves on every `establish()`. */
    fun nextFdEpoch(): Long = fdEpochSeq.incrementAndGet()

    fun currentFdEpoch(): Long = fdEpochSeq.get()

    fun isCurrent(generation: Long): Boolean = state.get().generation == generation

    /**
     * Writes [next] when it still belongs to the newest generation.
     *
     * Equal numbers are allowed on purpose: one transaction publishes `Starting`, then
     * `Stopping`, then `Active` under the same number, and those are its own steps. [why]
     * is the entry that asked for the move — a button, a row, Quick Settings, a revoke —
     * and it is part of the record, not of the logging: the one line per transition is
     * written from here so no path can move the tunnel without saying who asked.
     */
    fun publish(next: PortalRuntime, why: String = ""): Boolean {
        while (true) {
            val seen = state.get()
            if (next.generation < seen.generation) {
                GlobalState.log(
                    "$TAG refused a stale state: ${next.describe()} (current ${seen.describe()})",
                )
                return false
            }
            if (state.compareAndSet(seen, next)) {
                GlobalState.log("$TAG ${next.describe()}${if (why.isEmpty()) "" else " why=$why"}")
                for (observer in observers) {
                    // One reader failing must not cost the others their update, and it must
                    // not unwind the publish that already happened.
                    runCatching { observer(seen, next, why) }
                        .onFailure { error -> GlobalState.log("$TAG observer failed: ${error.message}") }
                }
                return true
            }
        }
    }

    /**
     * Takes the tunnel away without waiting for anybody.
     *
     * A revoke arrives from the system while a switch may be holding the coordinator's
     * mutex, and a revoke that waited for that mutex would leave the descriptor being read
     * by a core the system has already cut off. It fences instead: a new generation is
     * minted, `Off` is published under it, and the transaction in flight finds its own
     * number stale wherever it next reports.
     */
    fun revoke(reason: String, owner: PortalOwner? = state.get().owner): Long {
        val generation = nextGeneration()
        publish(PortalRuntime.Off(generation))
        GlobalState.log("$TAG revoked owner=${owner?.label ?: "none"} reason=$reason")
        return generation
    }
}
