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
}

/**
 * The single hand-over point between the service that makes the tunnel and the plugin that
 * starts the child.
 *
 * The two live in different Gradle modules but the same process, so the order is fixed: the
 * service publishes as its start returns and the plugin takes right after. A take clears the
 * slot, so two children can never be handed the same tunnel.
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
     * a race the child would lose by a few milliseconds.
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
 * The process that reads the tunnel, so the service can take it down together with the tun.
 *
 * The service cannot see the plugin (the module dependency runs the other way), and a child
 * left alive after the VPN is revoked keeps its own copy of the descriptor open: the
 * interface would outlive the run and go on carrying traffic nobody asked for. The plugin
 * registers here; the service calls it before it closes the descriptor it owns.
 */
object XrayChildControl {
    @Volatile
    var stop: (() -> Unit)? = null
}
