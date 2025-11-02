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

BACKEND_DIR="${TARGET_DIR}/ego/backend"

echo "[EGO] Installing backend dependencies..."
pushd "${BACKEND_DIR}" >/dev/null

NODE_BIN="${BACKEND_DIR}/.node/bin/node"
if [[ -x "${NODE_BIN}" ]]; then
  export PATH="$(dirname "${NODE_BIN}"):${PATH}"
  echo "[EGO] Using bundled Node runtime (${NODE_BIN})."
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  echo "[EGO] Using system Node runtime ($(command -v node))."
else
  cat <<'ERR' >&2
[EGO] Node.js 20.x is required. Install it first (e.g.):
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
and then rerun this script.
ERR
  exit 1
fi

npm install --silent
popd >/dev/null

echo "[EGO] Fetching frontend packages..."
pushd "${TARGET_DIR}/ego/frontend" >/dev/null
if command -v fvm >/dev/null 2>&1; then
  fvm flutter pub get
elif command -v flutter >/dev/null 2>&1; then
  flutter pub get
else
  echo "[EGO] Flutter SDK (또는 FVM)가 감지되지 않았습니다. Flutter 3.35.5 이상을 설치한 뒤 'flutter pub get'을 수동으로 실행하세요." >&2
fi
popd >/dev/null

cat <<'INFO'

[EGO] Installation complete.
- Backend: cd <target>/ego/backend && export PATH="$PWD/.node/bin:$PATH" && npm run start:dev
- Frontend: cd <target>/ego/frontend && flutter run -d web-server --dart-define=MIRROR_STAGE_WS_URL=http://10.0.0.100:3000/digital-twin --web-hostname=0.0.0.0 --web-port=8080

Remember to secure environment variables/secrets as needed.

INFO
