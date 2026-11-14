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

apply_series() {
  local dir="$1" mode="$2"
  local applied=0
  shopt -s nullglob
  local patches=("$PATCH_DIR"/*.patch)
  [[ ${#patches[@]} -gt 0 ]] || die "no patches in $PATCH_DIR"
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
    echo "base: $ref ($(git -C "$REPO" log -1 --format='%h %s' "$ref"))"
    rm -rf "$WORK" 2>/dev/null || die "$WORK exists and cannot be removed — move it away first"
    git clone --quiet --no-hardlinks "$REPO" "$WORK"
    git -C "$WORK" checkout --quiet -B portal "$ref"
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
    tmp=$(mktemp -d)
    git clone --quiet --no-hardlinks "$REPO" "$tmp/v"
    git -C "$tmp/v" checkout --quiet -B verify "$ref"
    for p in "$PATCH_DIR"/*.patch; do git -C "$tmp/v" am --3way --quiet "$p"; done
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
  *)
    die "usage: $0 {apply|check|verify|upstream-log}"
    ;;
esac
