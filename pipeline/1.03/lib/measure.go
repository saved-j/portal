package main

// Delay measurement for a whole node list, in one core, with no local listeners.
//
// The mechanism is libXray's (XTLS/libXray, xray/ping_batch.go) and AndroidLibXrayLite's
// (2dust/AndroidLibXrayLite, libv2ray_utils.go): an instance whose only content is the
// outbounds, and a dial per node made through the dispatcher with the node's tag forced on
// the context. Nothing listens on 127.0.0.1, and — this is the point of the second slot —
// nothing touches the tunnel's own instance, so a sweep can run while the portal is up.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	corenet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/common/session"
	core "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/outbound"
	coreserial "github.com/xtls/xray-core/infra/conf/serial"
)

const (
	measureDelayFailed  int64 = -1
	measureDelayTimeout int64 = -2
	measureDefaultURL         = "https://www.gstatic.com/generate_204"
	measureDefaultLimit       = 16
	measureSweepLimit         = 4
	measureMaxLimit           = 32
	// measureMaxTimeoutMs is the longest one node's probe may take. Nothing in the app asks
	// for more than eight seconds; the cap exists so a wrong number cannot outlive the sweep.
	measureMaxTimeoutMs = 15_000
)

// measureMutex guards the measurement slot only. The tunnel's coreMutex is never taken here:
// a sweep must not be able to stop, or be stopped by, the portal's own child.
var (
	measureMutex    sync.Mutex
	measureInstance *core.Instance
)


// MeasureRow is one node's answer.
type MeasureRow struct {
	Tag   string `json:"tag"`
	Delay int64  `json:"delay"`
	Error string `json:"error,omitempty"`
}

// measureResult is what the caller gets back: the rows in the order the tags were given.
type measureResult struct {
	Rows []MeasureRow `json:"rows"`
}

// MeasureTags times every tag in `tags` through `configJSON`'s outbounds, concurrently.
//
// The instance lives for this call only. It holds no inbound, so it cannot be connected to
// from this process; the only way in is the dial below, which names its outbound.
func MeasureTags(configJSON string, tags []string, url string, timeoutMs int, limit int) ([]MeasureRow, error) {
	if len(tags) == 0 {
		return nil, errors.New("no tags to measure")
	}
	config, err := coreserial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return nil, fmt.Errorf("config load error: %w", err)
	}
	// The document's entry points are not part of a measurement. Removing them before the
	// build is what keeps the probe core from opening a listener the sweep does not want.
	config.Inbound = nil
	var essential []*serial.TypedMessage
	for _, app := range config.App {
		if app.Type == "xray.app.proxyman.OutboundConfig" ||
			app.Type == "xray.app.dispatcher.Config" ||
			app.Type == "xray.app.log.Config" {
			essential = append(essential, app)
		}
	}
	config.App = essential

	// The measurement has its own slot: while a sweep runs, the portal's child keeps reading
	// the tunnel in its own instance. Only this slot is replaced, and only by a newer sweep.
	measureMutex.Lock()
	if measureInstance != nil {
		_ = measureInstance.Close()
		measureInstance = nil
	}
	inst, err := core.New(config)
	if err != nil {
		measureMutex.Unlock()
		return nil, fmt.Errorf("instance creation failed: %w", err)
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		measureMutex.Unlock()
		return nil, fmt.Errorf("startup failed: %w", err)
	}
	measureInstance = inst
	measureMutex.Unlock()
	defer func() {
		measureMutex.Lock()
		if measureInstance == inst {
			measureInstance = nil
			_ = inst.Close()
		}
		measureMutex.Unlock()
	}()

	if url == "" {
		url = measureDefaultURL
	}
	// A caller's number is a wish, not a contract: a timeout of a day would keep a worker and
	// the socket it holds for that day, and the channel that started it is long gone by then.
	// The ceiling is the sweep's own deadline (120 s) plus room for the answer to travel.
	if timeoutMs <= 0 {
		timeoutMs = 5000
	}
	if timeoutMs > measureMaxTimeoutMs {
		timeoutMs = measureMaxTimeoutMs
	}
	if limit <= 0 {
		limit = measureDefaultLimit
	}
	if limit > measureMaxLimit {
		limit = measureMaxLimit
	}

	// A tag the instance does not hold cannot be dialled: the dispatcher closes the pipe and
	// the caller gets a socket error that says nothing about the cause. Saying it here keeps
	// a mistyped tag a config fault instead of a node that "failed".
	manager, _ := inst.GetFeature(outbound.ManagerType()).(outbound.Manager)
	rows := make([]MeasureRow, len(tags))
	jobs := make(chan int)
	var workers sync.WaitGroup
	workers.Add(limit)
	for range limit {
		go func() {
			defer workers.Done()
			for index := range jobs {
				tag := tags[index]
				if manager != nil && manager.GetHandler(tag) == nil {
					rows[index] = MeasureRow{Tag: tag, Delay: measureDelayFailed, Error: "unknown outbound tag"}
					continue
				}
				rows[index] = probeTag(inst, tag, url, timeoutMs)
			}
		}()
	}
	for index := range tags {
		jobs <- index
	}
	close(jobs)
	workers.Wait()

	return rows, nil
}

// probeTag times one request carried by one outbound.
//
// The clock starts before the dial, so the node's own handshake is part of the number — that
// handshake is the node's work and a figure that started after it would flatter the node.
// The request is a HEAD, and the time is to the response *headers*: a body is throughput, not
// latency, and reading one would fold a download into a delay. libXray does the same
// (nodep/measure.go, PingHTTPRequest).
func probeTag(inst *core.Instance, tag string, url string, timeoutMs int) MeasureRow {
	timeout := time.Duration(timeoutMs) * time.Millisecond
	failure := MeasureRow{Tag: tag, Delay: measureDelayFailed}
	if tag == "" {
		failure.Error = "empty tag"
		return failure
	}

	// One transport per probe: keep-alives off and the pool never shared, or two nodes with
	// the same host would be timed by one connection and the second number would be a cache
	// hit.
	transport := &http.Transport{
		DisableKeepAlives: true,
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" && network != "tcp4" && network != "tcp6" {
				return nil, fmt.Errorf("unsupported probe network %q", network)
			}
			dest, err := corenet.ParseDestination("tcp:" + address)
			if err != nil {
				return nil, err
			}
			// The whole trick: the dispatcher takes the tag from the context and uses that
			// outbound instead of asking the router (app/dispatcher/default.go,
			// routedDispatch: "taking platform initialized detour").
			ctx = session.SetForcedOutboundTagToContext(ctx, tag)
			return core.Dial(ctx, inst, dest)
		},
	}
	defer transport.CloseIdleConnections()

	client := &http.Client{Transport: transport, Timeout: timeout}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodHead, url, nil)
	if err != nil {
		failure.Error = err.Error()
		return failure
	}
	req.Header.Set("User-Agent", "portal-delay")

	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		failure.NoAnswer(err)
		return failure
	}
	delay := time.Since(start).Milliseconds()
	// No body read at all: the headers are the latency; a body would be throughput.
	resp.Body.Close()

	if resp.StatusCode >= 400 {
		return MeasureRow{Tag: tag, Delay: measureDelayFailed, Error: resp.Status}
	}
	return MeasureRow{Tag: tag, Delay: delay}
}

// NoAnswer records a dial that raised, and says which kind it was.
func (r *MeasureRow) NoAnswer(err error) {
	r.Delay = measureDelayFailed
	if errors.Is(err, context.DeadlineExceeded) {
		r.Delay = measureDelayTimeout
		r.Error = "timeout"
		return
	}
	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		r.Delay = measureDelayTimeout
		r.Error = "timeout"
		return
	}
	r.Error = err.Error()
}

// XrayMeasure is the entry point the JNI layer exports:
//
//	XrayMeasure(configJSON, tagsJSON, url, timeoutMs) -> resultsJSON
//
// The body is what XrayPlugin.measureRun calls once per sweep.
// StopMeasure closes the measurement instance, if one is running. It never touches the
// tunnel's instance: a cancelled sweep stops the sweep and nothing else.
func StopMeasure() {
	measureMutex.Lock()
	defer measureMutex.Unlock()
	if measureInstance != nil {
		_ = measureInstance.Close()
		measureInstance = nil
	}
}

// measureSweep is what the C entry XrayMeasure calls once per sweep: JSON in, JSON out.
//
// Always answers a JSON document, even when it failed: the caller has one rule — free the
// string, parse it, look for `error` — instead of two.
func measureSweep(configJSON string, tagsJSON string, url string, timeoutMs int, limit int) string {
	var tags []string
	if err := json.Unmarshal([]byte(tagsJSON), &tags); err != nil {
		return measureErrorJSON(fmt.Sprintf("tags are not a JSON array of strings: %v", err))
	}
	if limit <= 0 {
		// Incy's own default: four full-proxy probes at a time. A node's handshake is the
		// expensive part and a wider pool measures contention, not the node.
		limit = measureSweepLimit
	}
	rows, err := MeasureTags(configJSON, tags, url, timeoutMs, limit)
	if err != nil {
		return measureErrorJSON(err.Error())
	}
	raw, err := json.Marshal(measureResult{Rows: rows})
	if err != nil {
		return measureErrorJSON(err.Error())
	}
	return string(raw)
}

func measureErrorJSON(message string) string {
	raw, _ := json.Marshal(map[string]string{"error": message})
	return string(raw)
}
