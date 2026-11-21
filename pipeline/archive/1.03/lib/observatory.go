package main

// The portal's own latency, read from the running core instead of measured by us.
//
// The child core is started on a document that holds every node of the subscription, one
// outbound each, with a `burstObservatory` whose subject selector names them: the core then
// times each node on its own schedule (`pingConfig.interval`) and keeps the results. This file
// reads those results — the same numbers a panel's dashboard shows for mihomo, for the same
// reason: they are measured by the core, not by the app, and no sweep has to run.
//
//	XrayObservatory() -> {"rows":[{"tag":"node-3","delay":214,"alive":true,"all":5,"fail":0}]}
//
// Nothing here measures anything. A row is missing until the core's first check of that node has
// finished, which is why the caller gets `sample` counts as well: a number built on one sample
// is not the same fact as a number built on five.

import (
	"context"
	"encoding/json"

	"github.com/xtls/xray-core/app/observatory"
	burst "github.com/xtls/xray-core/app/observatory/burst"
	"github.com/xtls/xray-core/features/extension"
)

// observatoryRow is one node's answer, in the shape the app reads.
type observatoryRow struct {
	Tag   string `json:"tag"`
	Delay int64  `json:"delay"`
	Alive bool   `json:"alive"`
	All   int64  `json:"all"`
	Fail  int64  `json:"fail"`
}

type observatoryRows struct {
	Rows []observatoryRow `json:"rows"`
	// Running is false when the core has no observatory: a document without `burstObservatory`
	// has nobody keeping such numbers, and the caller must fall back to asking the core.
	Running bool   `json:"running"`
	Reason  string `json:"reason,omitempty"`
}

// readObservatory answers the tags the running core is watching, and says why it cannot.
func readObservatory() string {
	coreMutex.Lock()
	instance := coreInstance
	coreMutex.Unlock()

	if instance == nil {
		return observatoryJSON(observatoryRows{Reason: "the core is not running"})
	}
	feature := instance.GetFeature(extension.ObservatoryType())
	if feature == nil {
		return observatoryJSON(observatoryRows{Reason: "the document declares no observatory"})
	}
	observer, ok := feature.(*burst.Observer)
	if !ok {
		// A plain `observatory` reports only what the balancer asked about, which is not the
		// subscription's whole list; the caller is told rather than shown half a list.
		return observatoryJSON(observatoryRows{Reason: "the document's observatory is not the burst one"})
	}
	message, err := observer.GetObservation(context.Background())
	if err != nil {
		return observatoryJSON(observatoryRows{Reason: err.Error()})
	}
	result, ok := message.(*observatory.ObservationResult)
	if !ok {
		return observatoryJSON(observatoryRows{Reason: "unexpected observation shape"})
	}
	rows := make([]observatoryRow, 0, len(result.Status))
	for _, status := range result.Status {
		// Two different units live in one message, which is the trap: `delay` is already
		// milliseconds (the core computes it with .Milliseconds()), while `health_ping` counters
		// are nanoseconds. Dividing the first again reported every node as 0 ms — a zero the
		// screen rightly draws as a dash.
		millis := status.Delay
		if millis <= 0 && status.HealthPing != nil {
			millis = (status.HealthPing.Average + 500000) / 1000000
		}
		row := observatoryRow{
			Tag:   status.OutboundTag,
			Delay: millis,
			Alive: status.Alive,
		}
		if status.HealthPing != nil {
			row.All = status.HealthPing.All
			row.Fail = status.HealthPing.Fail
		}
		// A node that has not answered in any sample has no delay: -1 says "asked, nothing".
		if !status.Alive || row.All == row.Fail {
			row.Delay = -1
		}
		rows = append(rows, row)
	}
	return observatoryJSON(observatoryRows{Rows: rows, Running: true})
}

func observatoryJSON(value observatoryRows) string {
	raw, err := json.Marshal(value)
	if err != nil {
		return `{"rows":[],"running":false,"reason":"cannot encode the answer"}`
	}
	return string(raw)
}
