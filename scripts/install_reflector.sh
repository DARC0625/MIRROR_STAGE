#!/usr/bin/env bash
#
# One-liner installer for MIRROR STAGE REFLECTOR agents.
# Usage: ./install_reflector.sh [<target_dir>]
# Default target: $HOME/mirror_stage_reflector

set -euo pipefail

REPO_URL="${MIRROR_STAGE_REPO:-https://github.com/DARC0625/MIRROR_STAGE.git}"
BRANCH="${MIRROR_STAGE_BRANCH:-main}"
TARGET_DIR="${1:-$HOME/mirror_stage_reflector}"

if [[ -e "${TARGET_DIR}" ]]; then
  echo "[REFLECTOR] Target directory ${TARGET_DIR} already exists. Aborting." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[REFLECTOR] git is required but not found in PATH." >&2
  exit 1
fi

TMP_DIR="${TARGET_DIR}.tmp"
rm -rf "${TMP_DIR}"

echo "[REFLECTOR] Cloning MIRROR STAGE (sparse) into ${TMP_DIR}..."
git clone --depth 1 --branch "${BRANCH}" --filter=blob:none --sparse "${REPO_URL}" "${TMP_DIR}"
pushd "${TMP_DIR}" >/dev/null
git sparse-checkout set reflector
popd >/dev/null

mv "${TMP_DIR}" "${TARGET_DIR}"

REFLECTOR_DIR="${TARGET_DIR}/reflector"

pushd "${REFLECTOR_DIR}" >/dev/null

if ! command -v python3 >/dev/null 2>&1; then
  echo "[REFLECTOR] python3 is required but not found." >&2
  exit 1
fi

if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "[REFLECTOR] python3-venv is required. Install the venv module." >&2
  exit 1
fi

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install --upgrade pip >/dev/null
pip install -r requirements.txt >/dev/null
deactivate
popd >/dev/null

rm -rf "${TARGET_DIR}/.git"
find "${TARGET_DIR}" -name '.git' -type d -prune -exec rm -rf {} + >/dev/null 2>&1 || true
rm -f "${TARGET_DIR}/.gitignore"

cat <<'INFO'

[REFLECTOR] Installation complete.
- Update reflector/config.json with the correct EGO endpoint (e.g., http://10.0.0.100:3000/api/metrics/batch).
- Start agent: cd <target>/reflector && ./start_reflector.sh
- Logs stream to reflector/logs/reflector.log (configurable).

Optional: export MIRROR_STAGE_REFLECTOR_CONFIG=<path> before start_reflector.sh to use a custom config file.

INFO
