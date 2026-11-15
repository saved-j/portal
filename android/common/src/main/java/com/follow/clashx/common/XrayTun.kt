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
) {
    /// The number the core is given. Valid only while [descriptor] is open.
    val fd: Int get() = descriptor.fd

    /// Whether the number above still names an open tunnel.
    ///
    /// A descriptor the service closed reports -1, and 0..2 are the process's own streams, so
    /// a number below 3 is not a tunnel. proxy/tun reads the number from the environment and
    /// falls back to 0 when it is unset, which is how a closed tunnel used to reach the core as
    /// a bare `inappropriate ioctl for device`.
    val live: Boolean get() = fd >= FIRST_TUN_FD

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

    @Volatile
    private var pending: XrayTun? = null

    fun publish(tun: XrayTun?) {
        pending = tun
    }

    fun take(): XrayTun? = pending?.also { pending = null }

    /**
     * Waits up to [timeoutMillis] for the service to publish.
     *
     * The service is started on the main thread and binds asynchronously, so the plugin can
     * genuinely arrive first; waiting is how a cold start becomes one ordered step instead of
     * a race the core would lose by a few milliseconds. It is also what replaces a dead
     * tunnel: a start whose cached descriptor was closed waits here for the VPN the service is
     * establishing now, instead of reading a number that already belongs to another file.
     */
    fun await(timeoutMillis: Long): XrayTun? {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            take()?.let { return it }
            Thread.sleep(POLL_MS)
        }
        return take()
    }

    fun clear() {
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
