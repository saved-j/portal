#!/bin/bash
# Publish a Portal release: tag → push → CI builds every platform → assets land in the
# GitHub release. Users download installers; nobody has to build anything.
#
#   ./release.sh v0.1.0            real release
#   ./release.sh v0.1.0 --draft    draft release (CI still uploads assets)
#
# Requires: gh authenticated (gh auth status), clean working tree, CI green on the commit.
set -euo pipefail

VERSION="${1:-}"
MODE="${2:-}"
[[ -n "$VERSION" ]] || { echo "usage: $0 vX.Y.Z [--draft]" >&2; exit 2; }
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: tag must look like v1.2.3" >&2; exit 2; }

REPO_DIR="${REPO_DIR:-$HOME/.work/portal}"
cd "$REPO_DIR"

git fetch --quiet origin
[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree is dirty — commit or stash first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && { echo "error: tag $VERSION already exists" >&2; exit 1; }

# The patch set must reproduce this tree, otherwise the release is not reproducible.
./apply.sh check

echo "tagging $VERSION on $(git log -1 --format='%h %s')"
git tag -a "$VERSION" -m "Portal $VERSION"
git push --quiet origin HEAD "$VERSION"
echo "pushed. CI: $(gh repo view --json nameWithOwner -q .nameWithOwner) → Actions → build"

if [[ "$MODE" == "--draft" ]]; then
  echo "note: CI creates the release; mark it draft afterwards in the web UI if needed"
fi

cat <<EOF

What users download from the release page (built by CI, not by them):
  macOS    FlClashX-*-macos-*.dmg        (or .zip)
  Windows  FlClashX-*-windows-*.zip      (or -setup.exe)
  Linux    FlClashX-*-linux-*.AppImage   (+ .deb/.rpm when packaged)
  Android  FlClashX-*-android-*.apk
  iOS      not built — the tree has no ios/ target yet
EOF
