package com.follow.clashx.common

import android.os.ParcelFileDescriptor

/**
 * The tunnel the VpnService established, and the facts the core needs to read it.
 *
 * A library cannot create a VpnService and cannot open the tunnel itself, so the service makes
 * it and states its facts here: the descriptor and the tunnel's own addresses. [descriptor]
 * stays owned by the service; the core only borrows the number, in this same process, and
 * reads it. Nothing here names the interface the core's own transport leaves by: that is the
 * service's uid exclusion (see `VpnService.keepCoreOutOfTunnel`), not a name.
 */
class XrayTun(
    val descriptor: ParcelFileDescriptor,
    val mtu: Int,
    val gateway: List<String>,
    val dns: List<String>,
    /// Which `establish()` made this tunnel. The service mints it, the plugin checks it, and
    /// a descriptor from an older epoch is never handed to a core of the newer one.
    val epoch: Long = 0L,
) {
    /// The number the core is given. Valid only while [descriptor] is open.
    // `ParcelFileDescriptor.getFd()` throws `IllegalStateException: Already closed` on a closed
    // descriptor instead of answering -1, and this getter is read on a worker thread at the
    // moment the service tears the tunnel down — that threw and killed the app. A closed tunnel
    // is a state to report, never an exception to propagate.
    val fd: Int get() = runCatching { descriptor.fd }.getOrDefault(-1)

    /// Whether this still names an open tunnel.
    ///
    /// The number alone is not enough: a descriptor the service closed reports -1, and its old
    /// number may already belong to the next file the process opened, so the descriptor itself
    /// is asked. proxy/tun falls back to 0 for a number that was never set, which is how a
    /// closed tunnel used to reach the core as a bare `inappropriate ioctl for device`.
    ///
    /// Both reads are guarded: `getFd()` *and* `getFileDescriptor()` throw
    /// `IllegalStateException: Already closed` on a descriptor the service just closed, and a
    /// reader has no business dying over the answer to a question it asked about a closing
    /// tunnel. A closed tunnel is `false`, never an exception.
    val live: Boolean get() = runCatching {
        val number = descriptor.fd
        number >= FIRST_TUN_FD && descriptor.fileDescriptor.valid()
    }.getOrDefault(false)

    /// A descriptor of its own, or `null` when this tunnel is no longer open.
    ///
    /// The one way to reach `dup()`: duplicating a closed descriptor throws
    /// `Already closed`, and a number taken from one belongs to whatever file the process
    /// opened next. The check and the duplicate happen under the same guard as [live], so a
    /// newer stop that closes the descriptor between them cannot slip through.
    @Synchronized
    fun duplicate(): ParcelFileDescriptor? {
        if (!live) return null
        return runCatching { descriptor.dup() }.getOrNull()
    }

    companion object {
        /// The first descriptor number that is not stdin, stdout or stderr: a tunnel is never
        /// one of them, and proxy/tun falls back to 0 for a number that was never set.
        const val FIRST_TUN_FD = 3
    }
}

/**
 * The single hand-over point between the service that makes the tunnel and the plugin that
 * starts the core.
 *
 * The two live in different Gradle modules but the same process, so the order is fixed: the
 * service publishes as its start returns and the plugin takes right after. A take clears the
 * slot, so one tunnel is never handed to two starts.
 */
object XrayTunHolder {
    private const val POLL_MS = 50L

    // One guard for the slot, the epoch and the take: `take` clears what `publish` set, and
    // two threads doing that beside each other is how one tunnel used to be handed to two
    // starts. Every operation below is written against this lock and nothing else.
    private val lock = Any()

    private var pending: XrayTun? = null

    /// The newest epoch this holder has seen, so an older publish cannot replace a newer one.
    private var publishedEpoch: Long = 0L

    fun publish(tun: XrayTun?) = synchronized(lock) {
        if (tun != null && tun.epoch in 1 until publishedEpoch) {
            GlobalState.log(
                "XrayTunHolder dropped a publish of an older epoch ${tun.epoch} " +
                    "(holding $publishedEpoch)",
            )
            return@synchronized
        }
        pending = tun
        if (tun != null && tun.epoch > publishedEpoch) publishedEpoch = tun.epoch
        Unit
    }

    /// The tunnel in hand, cleared as it is taken; an [epoch] given must match.
    fun take(epoch: Long? = null): XrayTun? = synchronized(lock) {
        val held = pending ?: return null
        if (epoch != null && epoch != held.epoch) return null
        pending = null
        held
    }

    /// The epoch of the newest tunnel the service published.
    fun currentEpoch(): Long = synchronized(lock) { publishedEpoch }

    /**
     * Waits up to [timeoutMillis] for the service to publish.
     *
     * The service is started on the main thread and binds asynchronously, so the plugin can
     * genuinely arrive first; waiting is how a cold start becomes one ordered step instead of
     * a race the core would lose by a few milliseconds. It is also what replaces a dead
     * tunnel: a start whose cached descriptor was closed waits here for the VPN the service is
     * establishing now, instead of reading a number that already belongs to another file.
     */
    fun await(timeoutMillis: Long, epoch: Long? = null): XrayTun? {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            take(epoch)?.let { return it }
            Thread.sleep(POLL_MS)
        }
        return take(epoch)
    }

    /// Drops the slot, and only the slot of [epoch] when one is given.
    ///
    /// A stop that names the tunnel it is closing must not clear the tunnel that replaced it:
    /// a newer `establish()` publishes while an older stop is still unwinding, and an
    /// unconditional clear left the newer descriptor reachable by nobody.
    fun clear(epoch: Long? = null) = synchronized(lock) {
        val held = pending ?: return@synchronized
        if (epoch != null && held.epoch > epoch) return@synchronized
        pending = null
    }
}

/**
 * The plugin's stop, for the service that owns the tunnel.
 *
 * The service cannot see the plugin (the module dependency runs the other way), and a core
 * left running after the VPN is revoked goes on reading a descriptor the system no longer
 * routes into: the plugin has to let go of the tunnel it was handed when the service closes
 * it. The plugin registers here; the service calls it before it closes the descriptor it owns.
 */
object XrayChildControl {
    @Volatile
    var stop: (() -> Unit)? = null
}

/// The measurement core, reached from the portal channel.
///
/// The core belongs to the xray plugin, which owns the library and its single instance; the
/// dashboard talks to the portal channel. These lambdas are the one line between them, set
/// when the xray plugin attaches and cleared when it goes — null means this build has no child
/// at all, which is exactly what the caller must hear.
object PortalMeasureBridge {
    @Volatile
    var start: ((String, String, String, Int, Int) -> Map<String, Any>)? = null

    @Volatile
    var stop: (() -> Boolean)? = null

    /// What the tunnel's own core has timed so far, without measuring anything. Set by the
    /// xray plugin; the dashboard reads it through this bridge because it speaks to the
    /// portal channel, not to the core's.
    @Volatile
    var observatory: (() -> Map<String, Any>)? = null
}
