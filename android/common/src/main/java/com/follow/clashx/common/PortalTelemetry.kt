package com.follow.clashx.common

import android.os.Process
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The portal's own record, in files `adb shell` can read.
 *
 * Everything the app wrote before lived in `filesDir`, and the shipped build is not
 * debuggable: `run-as` refuses it and nothing can be read off the device, so a defect on the
 * phone could only be described, never shown. These three files sit in the app's external
 * files directory instead — world-readable through adb on the phone — and the logcat mirror
 * stays exactly as it was.
 *
 *  - [STATUS_FILE] — a heartbeat every five seconds: owner, generation, tunnel epoch, phase,
 *    whether the engine runs, the app's own listening ports, and the last egress address
 *    seen by the probe;
 *  - [TRANSITIONS_FILE] — one line per transition: time, from → to, generation, why, result;
 *  - [XRAY_FILE] — the core's own log, the same file the tun document names.
 *
 * The paths are constants in this one place so the files can be found from the outside, and
 * `BUILD.md` names them for whoever reads a device next.
 */
object PortalTelemetry {
    /// File names, in the app's external files directory.
    const val STATUS_FILE = "portal-status.log"
    const val TRANSITIONS_FILE = "portal-transitions.log"
    const val XRAY_FILE = "xray.log"

    /// Where an earlier build kept the core's log, for a device that still has one.
    const val LEGACY_DIR = "xray-assets"

    private const val HEARTBEAT_MS = 5_000L
    private const val EGRESS_EVERY_TICKS = 6
    private const val MAX_LINES = 600
    private const val EGRESS_TIMEOUT_MS = 4_000
    private const val PORT_PROBE_MS = 200

    private val stamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US)

    private val started = AtomicBoolean(false)

    @Volatile
    private var lastEgress = "unknown"

    /// When the owner tapped the switch, and where the portal was going.
    ///
    /// A switch is measured from the tap, and only the record can say when the owner that
    /// took the tunnel acknowledged it, so the clock starts here — one channel call from the
    /// tap — and the `Active` line is written by [noteTransition], the same hook that writes
    /// every other transition. `0` means no switch is being measured.
    private val switchClickAt = java.util.concurrent.atomic.AtomicLong(0L)

    @Volatile
    private var switchFrom = "Off"

    @Volatile
    private var switchTo = "Off"

    /// Set by the app module, which is the only place that can see the service's runtime.
    @Volatile
    var engineProbe: () -> Boolean = { false }


    /// The port the app's cores should be listening on, for a table that cannot be read.
    ///
    /// `/proc/net/tcp` is a SELinux-denied read for an `untrusted_app` on this Android, so
    /// the kernel's own answer is not always available. The fallback is still a measurement,
    /// not a claim: a loopback TCP handshake against the port the options name, which only
    /// succeeds if something really is listening there.
    @Volatile
    var portProbe: () -> List<Int> = { emptyList() }

    /// The directory every file here lives in: external files, else the app's own.
    val logDir: File by lazy {
        val external = runCatching {
            GlobalState.application.getExternalFilesDir(null)
        }.getOrNull()
        val dir = external ?: File(GlobalState.application.filesDir, "telemetry")
        runCatching { if (!dir.exists()) dir.mkdirs() }
        dir
    }

    val statusFile: File get() = File(logDir, STATUS_FILE)
    val transitionsFile: File get() = File(logDir, TRANSITIONS_FILE)
    val xrayFile: File get() = File(logDir, XRAY_FILE)

    fun start() {
        if (!started.compareAndSet(false, true)) return
        // The one line per transition comes from the record, which is what makes it true
        // for every entry instead of only for the ones that remembered to write it.
        PortalRuntimeState.onPublish = ::noteTransition
        Thread({ loop() }, "portal-telemetry").apply {
            isDaemon = true
            start()
        }
        GlobalState.log("PortalTelemetry writing to ${logDir.absolutePath}")
    }

    private fun loop() {
        var tick = 0L
        while (true) {
            runCatching { writeStatus() }
                .onFailure { GlobalState.log("PortalTelemetry heartbeat failed: $it") }
            if (tick % EGRESS_EVERY_TICKS == 0L) {
                runCatching { probeEgress() }
                    .onFailure { GlobalState.log("PortalTelemetry egress probe failed: $it") }
            }
            tick++
            runCatching { Thread.sleep(HEARTBEAT_MS) }
        }
    }

    /// One heartbeat line, always in the same shape: the owner first, because that is the
    /// question every defect on this device came back to.
    fun writeStatus() {
        val runtime = PortalRuntimeState.current()
        val owner = runtime.owner?.label ?: "Off"
        val engine = if (engineProbe()) "running" else "stopped"
        // The child is not a separate probe: the record already says whether the child's
        // owner is the one reading the tunnel, and a second flag could only disagree.
        val child = if (runtime is PortalRuntime.Active && runtime.owner == PortalOwner.Xray) {
            "running"
        } else {
            "stopped"
        }
        val line = "time=${stamp.format(Date())} owner=$owner generation=${runtime.generation} " +
            "fdEpoch=${runtime.fdEpoch} phase=${runtime.phase} engine=$engine " +
            "child=$child " +
            "listeners=${listeners()} egress=$lastEgress"
        append(statusFile, line)
    }

    /// One line per transition of the record: who had it, who takes it, and why.
    ///
    /// Called from [PortalRuntimeState.publish], the one place a state is written, so no
    /// entry can move the tunnel without appearing here. A refusal of an older generation
    /// never reaches this: `publish` returns before it.
    fun noteTransition(seen: PortalRuntime, next: PortalRuntime, why: String) {
        val result = when (next) {
            is PortalRuntime.Failed -> "failed: ${next.reason}"
            is PortalRuntime.Active -> "ok fdEpoch=${next.fdEpoch}"
            else -> "ok"
        }
        append(
            transitionsFile,
            "time=${stamp.format(Date())} from=${seen.owner?.label ?: "Off"} " +
                "to=${next.owner?.label ?: "Off"} generation=${next.generation} " +
                "phase=${next.phase} why=${why.ifEmpty { "unsaid" }} result=$result",
        )
        if (next is PortalRuntime.Active) noteSwitchConfirmed(next)
    }

    /// The tap, from the screen that owns it: where the portal is going and when it started.
    fun noteSwitchStart(to: String) {
        switchTo = to
        switchFrom = PortalRuntimeState.current().owner?.label ?: "Off"
        switchClickAt.set(System.nanoTime())
    }

    /// Click → `phase=Active`, written once per tap, by the record's own hook.
    ///
    /// The owner's acknowledgement is the switch's end: `Active` is published only after the
    /// owner holds its listener or tunnel, so this number is the hand-over the owner sees, not
    /// a wait for a config. `0` means the tap was never registered — a transition from Quick
    /// Settings or a revoke — and those keep the plain line above and nothing invented.
    private fun noteSwitchConfirmed(next: PortalRuntime.Active) {
        val click = switchClickAt.getAndSet(0L)
        if (click == 0L) return
        val elapsedMs = (System.nanoTime() - click) / 1_000_000L
        append(
            transitionsFile,
            "time=${stamp.format(Date())} kind=switch phase=active " +
                "duration_ms=$elapsedMs from=$switchFrom to=${next.owner.label} " +
                "generation=${next.generation}",
        )
    }

    /// The screen's half of the same measurement: the tap → the list with rows in it.
    ///
    /// [durationMs] is the app's own clock, started before the tap asked anything, and
    /// [detail] says where the rows came from — the new owner's own answer (`source=live`),
    /// the last non-empty group the list drew (`source=held`), or the profile's `proxies:`
    /// (`source=profile`). The three are different facts and only the first is the new owner's.
    fun noteSwitchTiming(phase: String, durationMs: Long, detail: String) {
        val to = switchTo
        append(
            transitionsFile,
            "time=${stamp.format(Date())} kind=switch phase=$phase " +
                "duration_ms=$durationMs from=$switchFrom to=$to" +
                (if (detail.isEmpty()) "" else " $detail"),
        )
    }

    fun noteEgress(value: String) {
        lastEgress = value
    }

    /// The app's own listening sockets, from the kernel's own table.
    ///
    /// `/proc/net/tcp` is readable for the process's own sockets on Android; the uid column
    /// is what keeps every other app's out of the answer. A table that cannot be read says
    /// `unknown` instead of an empty list, because "nothing listens" and "nothing could be
    /// read" are different answers and only one of them is true.
    private fun listeners(): String {
        val uid = Process.myUid()
        val ports = mutableListOf<String>()
        var readable = false
        // `self` first: the per-process table is the one an app can sometimes still read.
        for (name in listOf("/proc/self/net/tcp", "/proc/self/net/tcp6")) {
            val lines = runCatching { File(name).readLines() }.getOrNull() ?: continue
            readable = true
            for (line in lines.drop(1)) {
                val fields = line.trim().split(Regex("\\s+"))
                if (fields.size < 8) continue
                // st == 0A is LISTEN; uid is column 7 in the kernel's own layout.
                if (fields[3] != "0A") continue
                if (fields[7] != uid.toString()) continue
                val address = decode(fields[1]) ?: continue
                ports.add(address)
            }
        }
        if (!readable) {
            return probePorts(portProbe()) ?: "unknown"
        }
        return ports.distinct().sorted().joinToString(",").ifEmpty { "none" }
    }

    /// The loopback ports that actually answer, measured rather than assumed.
    ///
    /// The options' own mixed port is only one candidate: a profile that never set
    /// `mixed-port` leaves it 0 while the cores still listen on their defaults, so the probe
    /// asks the known ports as well and reports the ones that answer. A port that refuses
    /// the handshake is not listed, which is what makes this a measurement.
    private fun probePorts(candidates: List<Int>): String? {
        val open = candidates.filter { it > 0 }.distinct().filter { port ->
            runCatching {
                java.net.Socket().use {
                    it.connect(java.net.InetSocketAddress("127.0.0.1", port), PORT_PROBE_MS)
                }
                true
            }.getOrDefault(false)
        }
        if (open.isEmpty()) return null
        return open.joinToString(",") { "probed:127.0.0.1:$it" }
    }

    /// `0100007F:2A3A` -> `127.0.0.1:10810`.
    private fun decode(local: String): String? {
        val parts = local.split(":")
        if (parts.size != 2) return null
        val hex = parts[0]
        val port = parts[1].toIntOrNull(16) ?: return null
        val bytes = hex.chunked(2).mapNotNull { it.toIntOrNull(16) }
        if (bytes.size != 4 && bytes.size != 16) return null
        val address = if (bytes.size == 4) {
            bytes.reversed().joinToString(".") { it.toString() }
        } else {
            // IPv6: the kernel writes four little-endian words; an all-zero address is `::`.
            if (bytes.all { it == 0 }) "::" else bytes.chunked(4)
                .reversed()
                .joinToString(":") { word -> word.joinToString("") { "%02x".format(it) } }
        }
        return "$address:$port"
    }

    /// The last public address this app's own traffic left by, or `unknown`.
    ///
    /// A probe from the app, so in the simple portal it leaves *outside* the tunnel by
    /// design (the service keeps this uid out of it) — it answers "is there egress at all,
    /// and where", not "which node is the portal on". A device-side `curl` is what proves
    /// the node's own address.
    private fun probeEgress() {
        val connection = runCatching {
            (URL("https://api.ipify.org").openConnection() as HttpURLConnection).apply {
                connectTimeout = EGRESS_TIMEOUT_MS
                readTimeout = EGRESS_TIMEOUT_MS
                requestMethod = "GET"
            }
        }.getOrNull() ?: return
        try {
            if (connection.responseCode !in 200..299) return
            val body = connection.inputStream.bufferedReader().use { it.readText() }.trim()
            if (body.isNotEmpty() && body.length <= 64) lastEgress = body
        } catch (_: Exception) {
            // Kept as the last value that answered: an unanswered probe is not a fact.
        } finally {
            runCatching { connection.disconnect() }
        }
    }

    private fun append(file: File, line: String) {
        synchronized(this) {
            runCatching {
                val parent = file.parentFile
                if (parent != null && !parent.exists()) parent.mkdirs()
                file.appendText(line + "\n", Charsets.UTF_8)
                // A log that grows without a bound is a file nobody can pull: the last
                // [MAX_LINES] lines are what a device check reads anyway.
                val lines = file.readLines()
                if (lines.size > MAX_LINES) {
                    file.writeText(lines.takeLast(MAX_LINES).joinToString("\n") + "\n")
                }
            }
        }
    }
}
