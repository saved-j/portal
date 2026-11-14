#!/bin/bash
# Portal = FlClashX upstream + our patches, applied in one pass.
#
#   ./apply.sh                 apply patches onto a clean upstream checkout (~/.work/portal-work)
#   ./apply.sh check           dry-run patches against the fork's working tree
#   ./apply.sh verify          prove patches/*.patch reproduce the fork's HEAD tree exactly
#   ./apply.sh upstream-log    show which upstream commits we are currently based on
#
# Source of truth is patches/*.patch, never the working tree. Updating upstream is:
#   git -C ~/.work/portal fetch upstream && ./apply.sh && ./build.sh macos
set -euo pipefail

REPO="${REPO:-$HOME/.work/portal}"
WORK="${WORK:-$HOME/.work/portal-work}"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/pluralplay/FlClashX.git}"
UPSTREAM_REF="${UPSTREAM_REF:-}"          # empty = upstream's default branch
PATCH_DIR="$REPO/patches"

die() { echo "error: $*" >&2; exit 1; }

MANIFEST="$PATCH_DIR/patches.json"
ONLY="${ONLY:-}"      # comma list of patch prefixes, e.g. ONLY=0010,0012
WITHOUT="${WITHOUT:-}" # comma list of patch prefixes to skip

# Print the enabled patch files, in manifest order, honouring ONLY/WITHOUT.
patch_series() {
  [[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST"
  python3 - "$MANIFEST" "$PATCH_DIR" "$ONLY" "$WITHOUT" <<'PY'
import json, sys
manifest, patch_dir, only, without = sys.argv[1:5]
data = json.load(open(manifest))
only = [p.strip() for p in only.split(',') if p.strip()]
without = [p.strip() for p in without.split(',') if p.strip()]
for entry in data.get('patches', []):
    name = entry['file']
    if not entry.get('enabled', True):
        continue
    if only and not any(name.startswith(p) for p in only):
        continue
    if without and any(name.startswith(p) for p in without):
        continue
    print(f"{patch_dir}/{name}")
PY
}

apply_series() {
  local dir="$1" mode="$2"
  local applied=0
  local patches=()
  while IFS= read -r line; do patches+=("$line"); done < <(patch_series)
  [[ ${#patches[@]} -gt 0 ]] || die "no enabled patches in $MANIFEST"
  for p in "${patches[@]}"; do
    local name; name=$(basename "$p")
    if [[ "$mode" == "check" ]]; then
      git -C "$dir" apply --check --3way "$p" && echo "ok   $name" || { echo "FAIL $name"; return 1; }
    else
      git -C "$dir" am --3way --quiet "$p" && echo "applied $name" || {
        git -C "$dir" am --abort 2>/dev/null || true
        die "$name did not apply cleanly — rebase it against the new upstream"
      }
    fi
    applied=$((applied + 1))
  done
  echo "total: $applied patch(es)"
}

cmd="${1:-apply}"
case "$cmd" in
  apply)
    [[ -d "$REPO/.git" ]] || die "fork repo not found at $REPO"
    git -C "$REPO" remote get-url upstream >/dev/null 2>&1 || \
      git -C "$REPO" remote add upstream "$UPSTREAM_URL"
    echo "fetching upstream..."
    git -C "$REPO" fetch --quiet upstream
    ref="${UPSTREAM_REF:-$(git -C "$REPO" symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null || echo upstream/main)}"
    # A fresh clone only carries origin's refs, so resolve the upstream ref to a SHA here.
    ref_sha=$(git -C "$REPO" rev-parse "$ref")
    echo "base: $ref ($(git -C "$REPO" log -1 --format='%h %s' "$ref"))"
    rm -rf "$WORK" 2>/dev/null || die "$WORK exists and cannot be removed — move it away first"
    git clone --quiet --no-hardlinks "$REPO" "$WORK"
    git -C "$WORK" checkout --quiet -B portal "$ref_sha"
    apply_series "$WORK" apply
    echo "ready: $WORK (branch portal)"
    ;;
  check)
    apply_series "$REPO" check
    ;;
  verify)
    # Rebuild the branch from upstream + patches and prove it matches the fork HEAD,
    # ignoring the pipeline's own files (patches/, apply.sh, docs/PIPELINE.md).
    git -C "$REPO" fetch --quiet upstream
    ref="${UPSTREAM_REF:-upstream/main}"
    ref_sha=$(git -C "$REPO" rev-parse "$ref")
    tmp=$(mktemp -d)
    git clone --quiet --no-hardlinks "$REPO" "$tmp/v"
    git -C "$tmp/v" checkout --quiet -B verify "$ref_sha"
    while IFS= read -r p; do git -C "$tmp/v" am --3way --quiet "$p"; done < <(patch_series)
    infra=(':!patches' ':!apply.sh' ':!build.sh' ':!release.sh' ':!docs/PIPELINE.md')
    if git -C "$tmp/v" diff --quiet HEAD "$(git -C "$REPO" rev-parse HEAD)" -- . "${infra[@]}"; then
      echo "OK: patches reproduce the fork tree (ignoring pipeline files)"
    else
      echo "MISMATCH: patches do not reproduce the fork tree" >&2
      git -C "$tmp/v" diff --stat HEAD "$(git -C "$REPO" rev-parse HEAD)" -- . "${infra[@]}" >&2
      exit 1
    fi
    ;;
  upstream-log)
    git -C "$REPO" fetch --quiet upstream
    git -C "$REPO" log --oneline -5 upstream/main
    echo "--- our patches ---"
    ls -1 "$PATCH_DIR"/*.patch | xargs -n1 basename
    ;;
  list)
    python3 - "$MANIFEST" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(f"{'patch':46} {'version':8} {'state':4} title")
for entry in data.get('patches', []):
    state = 'on' if entry.get('enabled', True) else 'off'
    print(f"{entry['file'][:46]:46} {entry.get('version','-'):8} {state:4} {entry.get('title','')}")
PY
    ;;
  *)
    die "usage: $0 {apply|check|verify|upstream-log|list}   [ONLY=0010,0012] [WITHOUT=0012]"
    ;;
esac
