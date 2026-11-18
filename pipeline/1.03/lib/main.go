// Package main implements a c-shared library wrapper around Xray-core.
//
// The library is intended to be loaded in-process by an Android app that
// already owns a VpnService tun file descriptor. Starting Xray in-process is
// required because a tun fd handed to a separate process cannot survive
// Runtime.exec (Android spawns children with POSIX_SPAWN_CLOEXEC_DEFAULT, so
// the fd is closed before the child is able to read it).
//
// The exported C API is:
//
//	char *XrayStart(char *configJSON, int tunFd, char *assetDir); // NULL on success, else error string
//	void  XrayStop(void);
//	char *XrayVersion(void);
//
// Every non-NULL char* returned here is allocated with C.CString (malloc) and
// must be released by the caller with free().
package main

/*
#include <stdlib.h>
#include <android/log.h>

// libxray_log is defined in jni_bridge.c: one line to logcat, which is the
// only console a library has inside an APK.
extern void libxray_log(const char *message);

#cgo LDFLAGS: -llog
*/
import "C"

import (
	"fmt"
	"os"
	"strconv"
	"sync"
	"unsafe"

	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all" // register all proxies / transports / features
	_ "github.com/xtls/xray-core/main/json"       // register the "json" config loader
	"golang.org/x/sys/unix"
)

// tunFdEnvKey is the environment variable Xray-core reads the tun file
// descriptor from (common/platform.TunFdKey, proxy/tun/tun_android.go).
// It has to be set in this very process before core.StartInstance runs.
const tunFdEnvKey = "xray.tun.fd"

// assetEnvKey is where the core looks for geosite.dat/geoip.dat.
const assetEnvKey = "xray.location.asset"

// libVersion is the wrapper's own version, independent of the Xray-core version.
const libVersion = 2

// firstTunFd is the lowest descriptor number a tunnel can have: 0, 1 and 2 are
// the process's standard streams, and proxy/tun falls back to 0 when
// xray.tun.fd is unset, which is a descriptor it will happily ioctl.
const firstTunFd = 3

var (
	coreMutex    sync.Mutex
	coreInstance *core.Instance
)

func errCString(msg string) *C.char {
	return C.CString("libxray: " + msg)
}

// logf writes one line to logcat under the libxray tag.
//
// Nothing else here can be seen on a device: an app process's stderr goes
// nowhere, and the core's own log file does not exist until a document names
// it, so a fault found before StartInstance would be invisible without this.
func logf(format string, args ...any) {
	message := C.CString(fmt.Sprintf(format, args...))
	defer C.free(unsafe.Pointer(message))
	C.libxray_log(message)
}

// checkTun answers whether fd is the tunnel the core is about to read.
//
// proxy/tun/tun_android.go takes the number from xray.tun.fd, sets it
// non-blocking and duplicates it; it never looks at what the descriptor is.
// A number that names anything else — a closed tunnel's number reused by the
// next file the app opened, or 0 because the variable was never set — reaches
// the core as a bare "inappropriate ioctl for device" from a TUNGETIFF the
// core does not explain. Checking here names the number, the ioctl, and what
// the descriptor actually is.
//
// The flags matter for the same reason: proxy/tun builds its fd reader with no
// virtio header (newFdTun(fd, 0)), so a tun carrying one would have its header
// parsed as the first bytes of every packet.
func checkTun(fd int) error {
	if fd < firstTunFd {
		return fmt.Errorf("fd %d is not a tunnel: 0..2 are the standard streams", fd)
	}
	var st unix.Stat_t
	if err := unix.Fstat(fd, &st); err != nil {
		return fmt.Errorf("fd %d is not open: %w", fd, err)
	}
	ifr, err := unix.NewIfreq("")
	if err != nil {
		return fmt.Errorf("tun fd %d: ifreq: %w", fd, err)
	}
	if err := unix.IoctlIfreq(fd, unix.TUNGETIFF, ifr); err != nil {
		return fmt.Errorf("fd %d is not a tun (TUNGETIFF: %w)", fd, err)
	}
	flags := ifr.Uint16()
	if flags&unix.IFF_TUN == 0 {
		return fmt.Errorf("fd %d is not a tun but a tap (flags %#x)", fd, flags)
	}
	if flags&unix.IFF_VNET_HDR != 0 {
		return fmt.Errorf("tun fd %d carries a virtio header the core would read as a packet (flags %#x)", fd, flags)
	}
	logf("tun fd %d is %q, flags %#x (IFF_TUN set, IFF_NO_PI %t)", fd, ifr.Name(), flags, flags&unix.IFF_NO_PI != 0)
	return nil
}

// stopLocked closes the running instance. Callers must hold coreMutex.
func stopLocked() {
	if coreInstance != nil {
		_ = coreInstance.Close()
		coreInstance = nil
	}
}

// XrayStart starts an Xray-core instance from a JSON configuration.
//
// tunFd > 0 makes the descriptor available to the "tun" inbound: it is
// published through the xray.tun.fd environment variable *in this process*
// before the core is created, which is the only way the inbound can pick it up
// without exec'ing a child process. The descriptor is checked first — it is the
// caller's interface, and the core's own error for a wrong one is an ioctl
// failure that names neither the number nor the cause.
//
// tunFd < 3 is an error, never a cleared variable. Clearing it makes
// proxy/tun fall back to fd "0" (tun_android.go), and a TUNGETIFF on stdin is
// the "inappropriate ioctl for device" that reads as a core fault: a caller
// that has no tunnel to give must not start a core that will ioctl one.
//
// XrayStart is idempotent: an instance that is already running is stopped and
// closed first. On success it returns NULL; on failure it returns a malloc'd
// error string that the caller must free().
//
// assetDir, when not empty, is exported as xray.location.asset *in this process*
// before the core is created: the core otherwise resolves geosite:/geoip: against
// the directory of os.Executable(), which inside an Android app is /system/bin and
// has no data files. The value must be set from here, not from Java: a child process
// inherits an environment, but an in-process library does not see a later setenv made
// by the JVM reliably enough to depend on it.
//
//export XrayStart
func XrayStart(configJSON *C.char, tunFd C.int, assetDir *C.char) *C.char {
	if configJSON == nil {
		return errCString("nil config")
	}
	config := C.GoString(configJSON)
	if assetDir != nil {
		if dir := C.GoString(assetDir); dir != "" {
			if err := os.Setenv(assetEnvKey, dir); err != nil {
				return errCString("set " + assetEnvKey + ": " + err.Error())
			}
		}
	}

	coreMutex.Lock()
	defer coreMutex.Unlock()

	// Idempotent restart: drop any previous instance before touching env state.
	stopLocked()

	// A negative number is a caller that has no tunnel to give: a measurement core, started on
	// a document whose listeners are local socks ports. It is not a cleared variable — the
	// environment is left alone, and 0..2 stay the error they were.
	if tunFd < 0 {
		instance, err := core.StartInstance("json", []byte(config))
		if err != nil {
			return errCString("start: " + err.Error())
		}
		coreInstance = instance
		return nil
	}
	if tunFd < firstTunFd {
		return errCString(fmt.Sprintf("tun: fd %d is not a tunnel: 0..2 are the standard streams", int(tunFd)))
	}
	fd := int(tunFd)
	if err := checkTun(fd); err != nil {
		return errCString("tun: " + err.Error())
	}
	if err := os.Setenv(tunFdEnvKey, strconv.Itoa(fd)); err != nil {
		return errCString("set " + tunFdEnvKey + ": " + err.Error())
	}

	instance, err := core.StartInstance("json", []byte(config))
	if err != nil {
		return errCString("start: " + err.Error())
	}
	coreInstance = instance

	return nil
}

// XrayStop stops the running instance, if any, and clears the reference.
// It is safe to call when nothing is running.
//
//export XrayStop
func XrayStop() {
	coreMutex.Lock()
	defer coreMutex.Unlock()

	stopLocked()
}

// XrayVersion returns the Xray-core version string, e.g. "26.11.9".
// The returned string is malloc'd and must be freed by the caller.
//
//export XrayVersion
func XrayVersion() *C.char {
	return C.CString(core.Version())
}

// XrayMeasure times every node of a document, in the measurement's own instance.
//
// Its instance is separate from the tunnel's on purpose: a sweep runs beside the portal
// instead of closing it. The answer is JSON — `{"rows":[{tag,delay,error}]}` — and it is
// always malloc'd, even when the call failed, so the C side has one rule for freeing it.
//
//export XrayMeasure
func XrayMeasure(configJSON *C.char, tagsJSON *C.char, url *C.char, timeoutMs C.int, limit C.int) *C.char {
	answer := measureSweep(
		C.GoString(configJSON), C.GoString(tagsJSON), C.GoString(url), int(timeoutMs), int(limit),
	)
	return C.CString(answer)
}

// XrayObservatory answers the latency the running core keeps for its own outbounds.
//
// It measures nothing: the document the child was started on declares a observatory, the core
// times every node on its own schedule, and this returns what it has. That is the same source
// mihomo's dashboard reads, and it costs the app nothing per row.
//
//export XrayObservatory
func XrayObservatory() *C.char {
	return C.CString(readObservatory())
}

// XrayMeasureStop closes the measurement instance and leaves the tunnel's alone.
//
//export XrayMeasureStop
func XrayMeasureStop() {
	StopMeasure()
}

// main is required for -buildmode=c-shared but never runs.
func main() {}
