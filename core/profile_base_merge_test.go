package core

import (
	"testing"

	"go.yaml.in/yaml/v3"
)

// A profile carries its own proxies, and the host adds one of its own (the local Xray).
// The merge must keep both, and must never let two entries share a name: mihomo refuses
// such a config, and one bad entry costs every proxy the user has.
func TestAppendByNameKeepsBothSides(t *testing.T) {
	added := list(t, "- name: XRAY-SOCKS\n  type: socks5\n  server: 127.0.0.1\n")
	profile := list(t, "- name: node-a\n  type: vless\n- name: node-b\n  type: trojan\n")

	merged, err := appendByName(added, profile)
	if err != nil {
		t.Fatalf("appendByName: %v", err)
	}
	names := namesOf(t, merged)
	if len(names) != 3 || names[0] != "XRAY-SOCKS" || names[1] != "node-a" || names[2] != "node-b" {
		t.Fatalf("want the host entry first then the profile's, got %v", names)
	}
}

func TestAppendByNameDropsDuplicates(t *testing.T) {
	added := list(t, "- name: XRAY-SOCKS\n  type: socks5\n")
	profile := list(t, "- name: XRAY-SOCKS\n  type: http\n- name: node-a\n  type: vless\n")

	merged, err := appendByName(added, profile)
	if err != nil {
		t.Fatalf("appendByName: %v", err)
	}
	names := namesOf(t, merged)
	if len(names) != 2 {
		t.Fatalf("want the duplicate dropped, got %v", names)
	}
	if names[0] != "XRAY-SOCKS" || names[1] != "node-a" {
		t.Fatalf("want the host's entry to win, got %v", names)
	}
}

func TestAppendByNameWithoutHostEntriesChangesNothing(t *testing.T) {
	profile := list(t, "- name: node-a\n  type: vless\n")
	merged, err := appendByName(nil, profile)
	if err != nil {
		t.Fatalf("appendByName: %v", err)
	}
	if merged != nil {
		t.Fatalf("want nil so the caller leaves the profile alone, got %v", namesOf(t, merged))
	}
}

func list(t *testing.T, src string) *yaml.Node {
	t.Helper()
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(src), &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(doc.Content) == 0 {
		t.Fatalf("empty document")
	}
	return doc.Content[0]
}

func namesOf(t *testing.T, node *yaml.Node) []string {
	t.Helper()
	if node == nil {
		return nil
	}
	out := make([]string, 0, len(node.Content))
	for _, item := range node.Content {
		out = append(out, nameOf(item))
	}
	return out
}
