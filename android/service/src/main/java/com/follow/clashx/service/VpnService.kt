package com.follow.clashx.service

import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.ProxyInfo
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import androidx.core.content.getSystemService
import com.follow.clashx.common.AccessControlMode
import com.follow.clashx.common.GlobalState
import com.follow.clashx.common.PortalRuntimeState
import com.follow.clashx.common.XrayChildControl
import com.follow.clashx.common.XrayTun
import com.follow.clashx.common.XrayTunHolder
import com.follow.clashx.common.R as CommonR
import com.follow.clashx.core.Core
import com.follow.clashx.service.models.CIDR
import com.follow.clashx.service.models.VpnOptions
import com.follow.clashx.service.models.ipv4Routes
import com.follow.clashx.service.models.ipv6Routes
import com.follow.clashx.service.models.toCIDR
import com.follow.clashx.service.models.tunMtu
import com.follow.clashx.service.models.tunOptions
import com.follow.clashx.service.modules.ServiceModules
import java.net.InetSocketAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import android.net.VpnService as SystemVpnService

class VpnService : SystemVpnService(), ManagedService {
    private val modules = ServiceModules(this)
    private val binder = LocalBinder()
    private val tunLock = Any()
    private var tunRunning = false

    /// Who reads the established descriptor: the engine, or the simple portal's child.
    private var tunOwnedByChild = false

    /// The simple portal's descriptor. The child borrows its number; the service keeps it.
    private var xrayDescriptor: ParcelFileDescriptor? = null

    /// The epoch of the descriptor in [xrayDescriptor], so a stop of an older tunnel cannot
    /// clear the newer one the service has already published.
    private var xrayEpoch = 0L

    override fun onDestroy() {
        try {
            cleanup()
        } finally {
            super.onDestroy()
        }
    }

    private val connectivity by lazy {
        getSystemService<ConnectivityManager>()
    }
    private val uidPackageNameMap = ConcurrentHashMap<Int, String>()

    private fun resolveUid(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
    ): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return -1
        }
        return connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
    }

    private fun resolvePackage(uid: Int): String {
        val cached = uidPackageNameMap[uid]
        if (cached != null) return cached
        val packageName = packageManager
            .getPackagesForUid(uid)
            ?.firstOrNull()
            ?.takeIf { it.isNotEmpty() }
            .orEmpty()
        return uidPackageNameMap.putIfAbsent(uid, packageName) ?: packageName
    }

    private val VpnOptions.tunAddress
        get(): String = buildString {
            append(IPV4_ADDRESS)
            if (ipv6) {
                append(",")
                append(IPV6_ADDRESS)
            }
        }

    private val VpnOptions.tunDns
        get(): String {
            if (dnsHijacking) {
                return NET_ANY
            }
            return buildString {
                append(DNS)
                if (ipv6) {
                    append(",")
                    append(DNS6)
                }
            }
        }

    override fun onLowMemory() {
        Core.forceGC()
        super.onLowMemory()
    }

    override fun onTrimMemory(level: Int) {
        trimCoreMemory(level)
        super.onTrimMemory(level)
    }

    inner class LocalBinder : Binder() {
        val service: VpnService
            get() = this@VpnService
    }

    override fun onBind(intent: Intent): IBinder? =
        if (intent.action == SystemVpnService.SERVICE_INTERFACE) {
            super.onBind(intent)
        } else {
            binder
        }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android starts always-on VPN through this callback instead of FlClash's bound-service
        // path. Notify the app layer so it can restore Core and fully initialize the VPN service.
        notifyVpnStartRequested()
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onRevoke() {
        // The system took the tunnel away, and it does not wait for a switch that may be
        // running: the record is fenced first, so a transaction in flight cannot publish its
        // `Active` over an interface that no longer exists. The stop below is the same one
        // every other close takes, and it is idempotent.
        PortalRuntimeState.revoke("vpn-permission-revoked")
        stop()
        notifyVpnRevoked()
    }

    private fun handleStart(options: VpnOptions) {
        // Whatever read the interface before this start goes first, whichever core it was.
        // `establish()` replaces the interface, and a previous reader left running either
        // reads a tunnel that no longer carries anything or — its descriptor still open —
        // keeps reading the new one beside the reader this start hands it to. The old
        // condition named the Xray case only (`tunOwnedByChild`), so a mihomo tunnel that
        // was still running survived the hand-over and became the second reader the simple
        // portal showed on the device.
        val previousOwner = synchronized(tunLock) {
            val owner = when {
                !tunRunning -> OWNER_OFF
                tunOwnedByChild -> OWNER_XRAY
                else -> OWNER_MIHOMO
            }
            stopTunLocked()
            owner
        }
        val owner = if (options.xrayTun) OWNER_XRAY else OWNER_MIHOMO
        // One number per established interface, minted here and carried by the tunnel the
        // child is handed: an acknowledgement that names an older epoch belongs to a
        // descriptor this start has already replaced.
        val fdEpoch = PortalRuntimeState.nextFdEpoch()
        GlobalState.log(
            "tun generation=${tunGeneration.incrementAndGet()} fdEpoch=$fdEpoch owner=$owner " +
                "previous=$previousOwner stopped=${previousOwner != OWNER_OFF}",
        )
        val descriptor = with(Builder()) {
            addAddressAndRoutes(options)
            addDnsServers(options)
            setMtu(options.tunMtu)
            configureAccessControl(options)
            keepCoreOutOfTunnel(options)
            setSession(getString(CommonR.string.app_name))
            setBlocking(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setMetered(false)
            }
            if (options.allowBypass) {
                allowBypass()
            }
            // The system proxy names the engine's mixed port, and in the simple portal no
            // engine runs: declaring it would send every app to a port nothing listens on.
            if (!options.xrayTun &&
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                options.systemProxy
            ) {
                GlobalState.log("Enable VPN HTTP proxy")
                setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        LOCAL_HOST,
                        options.port,
                        options.bypassDomain,
                    ),
                )
            }
            establish() ?: error("VPN establishment was rejected by the system")
        }
        if (options.xrayTun) {
            handOverToChild(descriptor, options, fdEpoch)
            return
        }
        val fd = descriptor.detachFd()
        synchronized(tunLock) {
            tunRunning = true
            try {
                // A Core that fails to take the descriptor leaves the system
                // routes pointing at an interface nothing reads, and it no
                // longer keeps its own sockets out of them: every connection
                // then hangs until it times out. Tear the VPN down instead of
                // reporting a start that only looks successful.
                check(
                    Core.startTun(
                        fd = fd,
                        protect = this::protect,
                        resolveUid = this::resolveUid,
                        resolvePackage = this::resolvePackage,
                        stack = options.stack,
                        address = options.tunAddress,
                        dns = options.tunDns,
                        options = options.tunOptions,
                    ),
                ) { "Core rejected the tun file descriptor" }
            } catch (error: Exception) {
                stopTunLocked()
                throw error
            }
        }
    }

    /**
     * The simple portal's tunnel: no engine is started, and the descriptor goes to the core.
     *
     * The core runs inside this process, so the sockets it opens for the node carry this app's
     * uid — and that uid is the one the tunnel must not route. [keepCoreOutOfTunnel] is what
     * states that, in the only way Android lets an app state it. Nothing here resolves an
     * interface for the core: an interface name would be a second, weaker spelling of the same
     * fact, and the core's own path for using one reads the interface table over rtnetlink,
     * which an app uid cannot do.
     */
    private fun handOverToChild(
        descriptor: ParcelFileDescriptor,
        options: VpnOptions,
        fdEpoch: Long,
    ) {
        synchronized(tunLock) {
            // The previous tunnel was taken down in handleStart, before this establish: the
            // system routes into the interface this start has just replaced, and the reader
            // that was on it is stopped — the child told to stop, the descriptor this service
            // owns closed — before another is published. A live number left behind would be
            // the second reader again.
            tunOwnedByChild = true
            tunRunning = true
            xrayDescriptor = descriptor
            xrayEpoch = fdEpoch
            XrayTunHolder.publish(
                XrayTun(
                    descriptor = descriptor,
                    mtu = options.tunMtu,
                    gateway = listOf(IPV4_ADDRESS),
                    dns = listOf(DNS),
                    epoch = fdEpoch,
                ),
            )
            GlobalState.log("tun fdEpoch=$fdEpoch owner=$OWNER_XRAY published for the core")
        }
    }

    private fun Builder.addAddressAndRoutes(options: VpnOptions) {
        val ipv4Address = IPV4_ADDRESS.toCIDR()
        addAddress(ipv4Address.address, ipv4Address.prefixLength)
        addRoutes(options.ipv4Routes(), fallbackAddress = NET_ANY)

        if (options.ipv6) {
            try {
                val ipv6Address = IPV6_ADDRESS.toCIDR()
                addAddress(ipv6Address.address, ipv6Address.prefixLength)
            } catch (_: Exception) {
                GlobalState.log("IPv6 VPN address is not supported")
            }
            addRoutes(options.ipv6Routes(), fallbackAddress = NET_ANY6)
        }
    }

    // Flutter lists every family it routes, so a family missing from a
    // non-empty list is one whose routes were all excluded.
    private fun Builder.addRoutes(routes: List<CIDR>?, fallbackAddress: String) {
        if (routes == null) {
            addRoute(fallbackAddress, 0)
            return
        }
        try {
            routes.forEach { route ->
                addRoute(route.address, route.prefixLength)
            }
        } catch (_: Exception) {
            addRoute(fallbackAddress, 0)
        }
    }

    private fun Builder.addDnsServers(options: VpnOptions) {
        addDnsServer(DNS)
        if (options.ipv6) {
            addDnsServer(DNS6)
        }
    }

    /// Keeps this app's own traffic out of the tunnel it reads, by uid.
    ///
    /// The simple portal's core is a library in this process, so every socket it opens for the
    /// node carries this app's uid. Without an exclusion the system would route that socket
    /// straight back into the tun the core is reading: the core would send its own node traffic
    /// into itself, and the connection would never leave the device. Android's answer is the
    /// per-uid one — `addDisallowedApplication` makes the VPN install no route into the tun for
    /// this package — which is what `VpnService.protect` does for a single socket and what
    /// `autoOutboundsInterface` would have said in the core's own words. It is the only one that
    /// works here: the core resolves that setting with `net.InterfaceByName`, and reading the
    /// interface table over rtnetlink is denied to an app uid.
    private fun Builder.keepCoreOutOfTunnel(options: VpnOptions) {
        if (!options.xrayTun) return
        val accessControl = options.accessControlProps
        // In whitelist mode the core is already out of the tunnel: `configureAccessControl`
        // never names this app, so nothing routes it. Android refuses a builder that mixes the
        // allowed and disallowed sets, and this call would be the one that mixes them.
        if (accessControl.enable && accessControl.mode == AccessControlMode.ACCEPT_SELECTED) {
            return
        }
        try {
            addDisallowedApplication(packageName)
        } catch (throwable: Exception) {
            // Reported instead of ignored: a tunnel that routes the core's own transport is one
            // that carries nothing, and pretending to have it start is worse than not starting.
            error("the portal core cannot be kept out of its own tunnel: ${throwable.message}")
        }
    }

    private fun Builder.configureAccessControl(options: VpnOptions) {
        val accessControl = options.accessControlProps
        if (!accessControl.enable) return
        when (accessControl.mode) {
            AccessControlMode.ACCEPT_SELECTED -> {
                // A package cannot be both allowed and disallowed, and the simple portal's core
                // is this app: it stays out of the tunnel (keepCoreOutOfTunnel) rather than in
                // it, so this list never names this app.
                val names = if (options.xrayTun) {
                    accessControl.acceptList - packageName
                } else {
                    accessControl.acceptList + packageName
                }
                names.forEach { name ->
                    addApplication(name, ::addAllowedApplication)
                }
            }

            AccessControlMode.REJECT_SELECTED -> {
                (accessControl.rejectList - packageName).forEach { name ->
                    addApplication(name, ::addDisallowedApplication)
                }
            }
        }
    }

    // A selected package that was uninstalled since must not veto the whole tunnel.
    private fun addApplication(name: String, add: (String) -> Builder) {
        try {
            add(name)
        } catch (_: PackageManager.NameNotFoundException) {
            GlobalState.log("Access control skipped an uninstalled package: $name")
        }
    }

    override fun start() {
        try {
            modules.start()
            handleStart(requireNotNull(ServiceConfig.vpnOptions) { "VPN options are missing" })
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    override fun stop() {
        try {
            cleanup()
        } finally {
            stopSelf()
        }
    }

    private fun cleanup() {
        try {
            modules.stop()
        } finally {
            stopTun()
        }
    }

    private fun stopTun() = synchronized(tunLock) {
        stopTunLocked()
    }

    private fun stopTunLocked() {
        if (!tunRunning) return
        val owner = if (tunOwnedByChild) OWNER_XRAY else OWNER_MIHOMO
        if (tunOwnedByChild) {
            // The child goes first: it holds its own copy of the descriptor, and a process
            // left reading a revoked tunnel keeps the interface alive for as long as it runs.
            XrayChildControl.stop?.invoke()
            // Only this tunnel's slot: a newer establish may already have published the
            // descriptor of the next generation, and clearing it would leave that one
            // reachable by nobody.
            XrayTunHolder.clear(xrayEpoch)
            xrayDescriptor?.let { descriptor ->
                runCatching { descriptor.close() }
                    .onFailure { GlobalState.log("Unable to close the Xray tunnel: $it") }
            }
            xrayDescriptor = null
            xrayEpoch = 0L
            tunOwnedByChild = false
        } else {
            Core.stopTun()
        }
        tunRunning = false
        GlobalState.log(
            "tun generation=${tunGeneration.get()} owner=$owner released, owner=$OWNER_OFF",
        )
    }

    companion object {
        /// Numbers each established tunnel across service instances, so the log tells one
        /// hand-over from the next: the service stops between a close and the next start, so
        /// a per-instance counter would call every tunnel the first one.
        private val tunGeneration = AtomicInteger(0)

        // Who reads the established tunnel: nothing, the engine, or the child. Spelled in the
        // log, because a number alone cannot say which core a start took the interface from.
        private const val OWNER_OFF = "Off"
        private const val OWNER_MIHOMO = "Mihomo"
        private const val OWNER_XRAY = "Xray"

        // mihomo's own TUN default: 198.18.0.0/15 is benchmarking space no LAN
        // uses, and its fake-ip pool starts at .4, past this /30.
        private const val IPV4_ADDRESS = "198.18.0.1/30"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
        private const val DNS = "198.18.0.2"
        private const val DNS6 = "fdfe:dcba:9876::2"
        private const val NET_ANY = "0.0.0.0"
        private const val NET_ANY6 = "::"
        private const val LOCAL_HOST = "127.0.0.1"
    }
}
