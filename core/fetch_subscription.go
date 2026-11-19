package core

import (
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"time"
)

// fetchSubscriptionParams is one request on behalf of the app.
type fetchSubscriptionParams struct {
	URL       string `json:"url"`
	UserAgent string `json:"userAgent"`
}

// fetchSubscriptionReply is the whole answer: the body and the headers it came with.
//
// The headers are not decoration: the panel puts the plan's title, its traffic counters and
// the update interval there, and the app shows all three.
type fetchSubscriptionReply struct {
	Status  int                 `json:"status"`
	Headers map[string][]string `json:"headers"`
	Body    string              `json:"body"`
}

// handleFetchSubscription fetches a subscription body with the core's own HTTP client.
//
// A panel may answer the same client name differently depending on who is asking: the
// engine's client is the one it was written for, and another TLS stack can be served a
// generic Clash fallback instead of the document with the panel's own notes. Doing the fetch
// here means the app parses the body the engine would have received.
func handleFetchSubscription(params fetchSubscriptionParams) (fetchSubscriptionReply, error) {
	request, err := http.NewRequest(http.MethodGet, params.URL, nil)
	if err != nil {
		return fetchSubscriptionReply{}, err
	}
	if params.UserAgent != "" {
		request.Header.Set("User-Agent", params.UserAgent)
	}
	client := &http.Client{Timeout: 45 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return fetchSubscriptionReply{}, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 32<<20))
	if err != nil {
		return fetchSubscriptionReply{}, err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fetchSubscriptionReply{}, fmt.Errorf("http %d", response.StatusCode)
	}
	return fetchSubscriptionReply{
		Status:  response.StatusCode,
		Headers: response.Header,
		Body:    base64.StdEncoding.EncodeToString(body),
	}, nil
}
