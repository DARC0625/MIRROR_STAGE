#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${ROOT_DIR}/.venv"
LOG_DIR="${ROOT_DIR}/logs"
PID_FILE="${ROOT_DIR}/reflector.pid"

mkdir -p "${LOG_DIR}"

if [[ ! -f "${VENV}/bin/python" ]]; then
  echo "virtualenv not found. Run: python3 -m venv ${VENV}" >&2
  exit 1
fi

if [[ -f "${PID_FILE}" ]]; then
  if kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
    echo "REFLECTOR already running with PID $(cat "${PID_FILE}")." >&2
    exit 0
  else
    rm -f "${PID_FILE}"
  fi
fi

echo "Starting MIRROR STAGE REFLECTOR..."

(
  source "${VENV}/bin/activate"
  export PYTHONPATH="${ROOT_DIR}/src"
  export PYTHONUNBUFFERED=1
  nohup "${VENV}/bin/python" -m agent.uplink >> "${LOG_DIR}/reflector.log" 2>&1 &
  echo $! > "${PID_FILE}"
)

echo "REFLECTOR started. Logs: ${LOG_DIR}/reflector.log"
