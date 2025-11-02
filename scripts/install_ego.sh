#!/usr/bin/env bash
#
# One-liner installer for MIRROR STAGE EGO (control-plane) stack.
# Usage: ./install_ego.sh [<target_dir>]
# Default target: $HOME/mirror_stage_ego

set -euo pipefail

REPO_URL="${MIRROR_STAGE_REPO:-https://github.com/DARC0625/MIRROR_STAGE.git}"
BRANCH="${MIRROR_STAGE_BRANCH:-main}"
TARGET_DIR="${1:-$HOME/mirror_stage_ego}"

if [[ -e "${TARGET_DIR}" ]]; then
  echo "[EGO] Target directory ${TARGET_DIR} already exists. Aborting." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[EGO] git is required but not found in PATH." >&2
  exit 1
fi

echo "[EGO] Cloning MIRROR STAGE repository (${BRANCH}) into ${TARGET_DIR}..."
git clone --depth 1 --branch "${BRANCH}" "${REPO_URL}" "${TARGET_DIR}"

echo "[EGO] Installing backend dependencies..."
pushd "${TARGET_DIR}/ego/backend" >/dev/null
if [[ ! -x ".node/bin/node" ]]; then
  echo "[EGO] Bundled Node runtime (.node/bin/node) not found. Ensure repo is intact." >&2
  exit 1
fi
export PATH="$(pwd)/.node/bin:${PATH}"
npm install --silent
popd >/dev/null

echo "[EGO] Fetching frontend packages..."
pushd "${TARGET_DIR}/ego/frontend" >/dev/null
if command -v fvm >/dev/null 2>&1; then
  fvm flutter pub get
elif command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo "[EGO] Flutter SDK (or FVM) not found. Install Flutter 3.35.5+ and re-run pub get." >&2
fi
popd >/dev/null

cat <<'INFO'

[EGO] Installation complete.
- Backend: cd <target>/ego/backend && export PATH="$PWD/.node/bin:$PATH" && npm run start:dev
- Frontend: cd <target>/ego/frontend && flutter run -d web-server --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin --web-hostname=0.0.0.0 --web-port=8080

Remember to secure environment variables/secrets as needed.

INFO
