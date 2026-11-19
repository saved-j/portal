#!/bin/bash
# Portal patch dispatcher.
#
#   ./apply.sh list                 what series exist
#   ./apply.sh 0.02 verify          apply the groups to pristine FlClashX and prove the result
#   ./apply.sh 0.02 apply [dir]     materialise a working copy (default ~/.work/portal-0.02)
#
# 0.02 is a grouped series: each group is a binary diff of the product tree against the pinned
# base and the groups are path-disjoint, so plain `git am` applies them in any order with no
# --3way. 0.01a is the frozen 48-patch history: kept for audit, NOT replayable (its icon
# patches conflict with each other), so the dispatcher refuses to apply it and says why.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE="$REPO/pipeline"
CURRENT="$(cat "$PIPELINE/CURRENT" 2>/dev/null || echo 0.02)"
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

list_series() {
  echo "current: $CURRENT"
  for d in "$PIPELINE"/*/; do
    [[ -f "$d/REGISTRY.json" ]] || continue
    python3 - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]
r = json.load(open(os.path.join(d, 'REGISTRY.json')))
base = (r.get('base') or {}).get('sha', '-')[:8]
items = r.get('groups') or r.get('patches') or []
state = r.get('state', 'live')
print(f"  {os.path.basename(d.rstrip('/')):8s} base {base}  items {len(items):3d}  {state}")
PY
  done
}

series_dir() {
  local v=$1
  [[ -d "$PIPELINE/$v" ]] || die "no such series: $v (see ./apply.sh list)"
  echo "$PIPELINE/$v"
}

gate() {
  local dir=$1
  [[ -f "$dir/REGISTRY.json" ]] || die "missing REGISTRY.json in $dir"
  python3 - "$dir" <<'PY'
import hashlib, json, os, sys
d = sys.argv[1]
r = json.load(open(os.path.join(d, 'REGISTRY.json')))
items = r.get('groups') or r.get('patches') or []
if not items:
    raise SystemExit('registry lists no items')
for it in items:
    p = os.path.join(d, it['file'])
    if not os.path.isfile(p):
        raise SystemExit(f"missing patch: {p}")
    if os.path.getsize(p) == 0:
        raise SystemExit(f"empty patch: {p}")
    want = it.get('sha256')
    got = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    if want and got != want:
        raise SystemExit(f"sha256 mismatch for {p}\n  registry {want}\n  on disk  {got}")
    head = open(p, 'rb').read(4)
    mode = r.get('apply', 'git-am')
    # A series is either an mbox series (git am) or a plain diff series (git apply).
    if mode == 'git-apply':
        if not head.startswith(b'diff'):
            raise SystemExit(f"not a git diff: {p}")
    elif not head.startswith(b'From'):
        raise SystemExit(f"not an mbox: {p}")
print(f"gate ok: {len(items)} item(s), checksums match")
PY
}

group_patches() { # prints full paths, in registry order
  local dir=$1
  python3 - "$dir" <<'PY'
import json, os, sys
d = sys.argv[1]
r = json.load(open(os.path.join(d, 'REGISTRY.json')))
for it in r.get('groups') or r.get('patches') or []:
    print(os.path.join(d, it['file']))
PY
}

verify() {
  local v=$1 dir; dir=$(series_dir "$v")
  local mode; mode=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json')).get('apply','git-am'))")
  [[ "$mode" == "git-apply" || "$v" == "0.02" ]] || die "$v is an archive; it is not replayable"

  gate "$dir"
  local sha base
  sha=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json'))['base']['sha'])")
  base=$(git -C "$REPO" rev-parse --verify --quiet "${sha}^{commit}") || die "base $sha is not in this repo — git fetch upstream"
  # A global, not a local: the EXIT trap runs after the function's scope is gone, and
  # `set -u` then fails on an unbound local.
  VERIFY_TMP=$(mktemp -d "${TMPDIR:-/tmp}/portal-verify.XXXXXX")
  trap 'rm -rf "${VERIFY_TMP:-}"' EXIT
  local tmp=$VERIFY_TMP
  git clone -q --no-hardlinks "$REPO" "$tmp/w"
  git -C "$tmp/w" checkout -q -B verify-0.02 "$base"
  local applied=0
  while IFS= read -r patch; do
    if [[ "$mode" == "git-apply" ]]; then
      if git -C "$tmp/w" apply --whitespace=nowarn "$patch"; then
        echo "  apply ok: $(basename "$patch")"
        applied=$((applied + 1))
        continue
      fi
      die "does not apply to pristine FlClashX: $patch"
    fi
    if git -C "$tmp/w" am --quiet "$patch"; then
      echo "  am ok: $(basename "$patch")"
      applied=$((applied + 1))
    else
      git -C "$tmp/w" am --abort 2>/dev/null || true
      die "does not apply to pristine FlClashX: $patch"
    fi
  done < <(group_patches "$dir")
  [[ $applied -gt 0 ]] || die "no groups applied"
  # A diff series leaves a dirty worktree; committing it is what makes the tree hash real.
  if [[ "$mode" == "git-apply" ]]; then
    git -C "$tmp/w" add -A >/dev/null
    git -C "$tmp/w" -c user.name=verify -c user.email=verify@local \
      commit -q -m "series $v" >/dev/null
  fi

  # Exact equality, not a file walk: hash the committed product tree of this repo with the
  # pipeline directory removed, and compare it with the tree the groups produced. Build
  # artefacts (build/, dist/, gradlew, local.properties, .DS_Store) never enter a commit,
  # so they cannot make this comparison lie.
  local wt idx
  local compare; compare=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json')).get('compare','product'))")
  # The series states the tree it must reproduce; that is the authority. HEAD may differ
  # because the series itself lives in a later commit, and a snapshot cannot contain itself.
  local declared; declared=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json')).get('tree',''))")
  if [[ -n "$declared" ]]; then
    wt=$declared
  elif [[ "$compare" == "full" ]]; then
    wt=$(git -C "$REPO" rev-parse 'HEAD^{tree}')
  else
    idx="$tmp/index"
    GIT_INDEX_FILE="$idx" git -C "$REPO" read-tree HEAD
    GIT_INDEX_FILE="$idx" git -C "$REPO" rm -r --cached --ignore-unmatch pipeline apply.sh >/dev/null
    wt=$(GIT_INDEX_FILE="$idx" git -C "$REPO" write-tree)
  fi


  local got
  if [[ "$compare" == "product" ]]; then
    # Both sides are compared as products: the pipeline directory is not part of the tree
    # a series reproduces, and the clone inherits the base's own pipeline copy.
    local gidx="$tmp/gindex"
    GIT_INDEX_FILE="$gidx" git -C "$tmp/w" read-tree HEAD
    GIT_INDEX_FILE="$gidx" git -C "$tmp/w" rm -r --cached --ignore-unmatch pipeline >/dev/null
    got=$(GIT_INDEX_FILE="$gidx" git -C "$tmp/w" write-tree)
  else
    got=$(git -C "$tmp/w" rev-parse 'HEAD^{tree}')
  fi

  if [[ "$wt" == "$got" ]]; then
    echo "OK: $applied group(s) reproduce the committed product tree ($wt)"
  else
    echo "MISMATCH: groups produced $got, the repository has $wt" >&2
    git -C "$tmp/w" diff --stat "$wt" "$got" 2>/dev/null | head -20 >&2 || true
    exit 1
  fi
}

apply_series() {
  local v=$1 dest=${2:-} dir; dir=$(series_dir "$v")
  local mode; mode=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json')).get('apply','git-am'))")
  [[ "$mode" == "git-apply" || "$v" == "0.02" ]] || die "$v is an archive and cannot be applied"
  gate "$dir"
  dest=${dest:-$HOME/.work/portal-$v}
  local sha; sha=$(python3 -c "import json;print(json.load(open('$dir/REGISTRY.json'))['base']['sha'])")
  [[ -e "$dest" ]] && die "destination exists: $dest (move it away first)"
  git clone -q --no-hardlinks "$REPO" "$dest"
  git -C "$dest" checkout -q -B "portal-$v" "$sha"
  while IFS= read -r patch; do
    if [[ "$mode" == "git-apply" ]]; then
      git -C "$dest" apply --whitespace=nowarn "$patch" || die "does not apply: $patch"
    else
      git -C "$dest" am --quiet "$patch" || die "does not apply: $patch"
    fi
  done < <(group_patches "$dir")
  echo "ready: $dest (branch portal-$v, base ${sha:0:8})"
}


case "${1:-}" in
  list|'') list_series ;;
  -h|--help|help) sed -n '2,12p' "$0" ;;
  *)
    v=$1; cmd=${2:-verify}
    case "$cmd" in
      verify) verify "$v" ;;
      apply)  apply_series "$v" "${3:-}" ;;
      *) die "unknown command: $cmd (verify|apply)" ;;
    esac
    ;;
esac
