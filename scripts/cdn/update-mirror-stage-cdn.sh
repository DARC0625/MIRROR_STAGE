#!/usr/bin/env bash
# Updates the darc.kr CDN payload with the latest MIRROR_STAGE source archive.

set -euo pipefail

REPO_DIR=${REPO_DIR:-/home/darc/mirror_stage/repo}
WEB_ROOT=${WEB_ROOT:-/var/www/html}
BRANCH=${BRANCH:-main}
ZIP_NAME=${ZIP_NAME:-mirror-stage-latest.zip}
VERSION_JSON=${VERSION_JSON:-mirror-stage-version.json}
SHA_FILE=${SHA_FILE:-mirror-stage-latest.sha}

log() {
  echo "[cdn-sync] $1"
}

log "Syncing repository at $REPO_DIR (branch: $BRANCH)"
cd "$REPO_DIR"
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"
git clean -fdx

TMP_ZIP="$(mktemp)"
trap 'rm -f "$TMP_ZIP"' EXIT
git archive --format=zip --output "$TMP_ZIP" "$BRANCH"

sha=$(git rev-parse HEAD)

log "Deploying artifacts to $WEB_ROOT"
sudo install -m 644 -o root -g root "$TMP_ZIP" "$WEB_ROOT/$ZIP_NAME"
printf '%s\n' "$sha" | sudo tee "$WEB_ROOT/$SHA_FILE" >/dev/null
printf '{"sha":"%s"}\n' "$sha" | sudo tee "$WEB_ROOT/$VERSION_JSON.tmp" >/dev/null
sudo mv "$WEB_ROOT/$VERSION_JSON.tmp" "$WEB_ROOT/$VERSION_JSON"

log "Deployment complete (sha: $sha)"
