#!/usr/bin/env bash
#
# One-liner installer for MIRROR STAGE REFLECTOR agents.
# Usage: ./install_reflector.sh [<target_dir>] [--endpoint <url>] [--command-endpoint <url>]
#        [--hostname <name>] [--rack <rack>] [--position x y z]
# Default target: $HOME/mirror_stage_reflector

set -euo pipefail

REPO_URL="${MIRROR_STAGE_REPO:-https://github.com/DARC0625/MIRROR_STAGE.git}"
BRANCH="${MIRROR_STAGE_BRANCH:-main}"
TARGET_DIR="${1:-$HOME/mirror_stage_reflector}"
shift || true

ENDPOINT=""
COMMAND_ENDPOINT=""
HOSTNAME_OVERRIDE=""
RACK=""
POS_X=""
POS_Y=""
POS_Z=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)
      ENDPOINT="$2"; shift 2 ;;
    --command-endpoint)
      COMMAND_ENDPOINT="$2"; shift 2 ;;
    --hostname)
      HOSTNAME_OVERRIDE="$2"; shift 2 ;;
    --rack)
      RACK="$2"; shift 2 ;;
    --position)
      POS_X="$2"; POS_Y="$3"; POS_Z="$4"; shift 4 ;;
    --help|-h)
      cat <<USAGE
Usage: ./install_reflector.sh [target_dir] [options]
Options:
  --endpoint <url>           Metrics endpoint (e.g. http://10.0.0.100:3000/api/metrics/batch)
  --command-endpoint <url>   Optional command endpoint (e.g. http://10.0.0.100:3000/api/commands)
  --hostname <name>          Hostname override for reports
  --rack <rack>              Rack label
  --position <x> <y> <z>     Position coordinates
USAGE
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1 ;;
  esac
done

read -p "EGO metrics endpoint [${ENDPOINT:-http://10.0.0.100:3000/api/metrics/batch}]: " INPUT || true
ENDPOINT=${INPUT:-${ENDPOINT:-http://10.0.0.100:3000/api/metrics/batch}}
read -p "Command endpoint (optional) [${COMMAND_ENDPOINT}]: " INPUT || true
COMMAND_ENDPOINT=${INPUT:-$COMMAND_ENDPOINT}
read -p "Hostname override (optional) [${HOSTNAME_OVERRIDE}]: " INPUT || true
HOSTNAME_OVERRIDE=${INPUT:-$HOSTNAME_OVERRIDE}
read -p "Rack (optional) [${RACK}]: " INPUT || true
RACK=${INPUT:-$RACK}
if [[ -z "$POS_X" ]]; then
  read -p "Position X (optional): " POS_X || true
  read -p "Position Y (optional): " POS_Y || true
  read -p "Position Z (optional): " POS_Z || true
fi

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

CONFIG_FILE="${REFLECTOR_DIR}/config.json"
python3 <<PY
import json
from pathlib import Path

config_path = Path("${CONFIG_FILE}")
config = {
    "endpoint": "${ENDPOINT}",
    "interval_seconds": 5.0,
}
if "${HOSTNAME_OVERRIDE}":
    config["hostname_override"] = "${HOSTNAME_OVERRIDE}"
if "${RACK}":
    config["rack"] = "${RACK}"
if "${POS_X}" and "${POS_Y}" and "${POS_Z}":
    try:
        config["position"] = {
            "x": float("${POS_X}"),
            "y": float("${POS_Y}"),
            "z": float("${POS_Z}"),
        }
    except ValueError:
        config["position"] = {
            "x": "${POS_X}",
            "y": "${POS_Y}",
            "z": "${POS_Z}",
        }
if "${COMMAND_ENDPOINT}":
    config["command_endpoint"] = "${COMMAND_ENDPOINT}"
    config["command_poll_seconds"] = 15

with config_path.open("w", encoding="utf-8") as fh:
    json.dump(config, fh, indent=2)
    fh.write("\\n")
PY

deactivate
popd >/dev/null

rm -rf "${TARGET_DIR}/.git"
find "${TARGET_DIR}" -name '.git' -type d -prune -exec rm -rf {} + >/dev/null 2>&1 || true
rm -f "${TARGET_DIR}/.gitignore"

cat <<INFO

[REFLECTOR] Installation complete.
- Config: ${CONFIG_FILE}
- Start agent: cd ${TARGET_DIR}/reflector && ./start_reflector.sh
- Logs stream to reflector/logs/reflector.log

INFO
