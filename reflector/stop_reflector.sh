#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${ROOT_DIR}/reflector.pid"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "No PID file found. REFLECTOR might not be running."
  exit 0
fi

PID="$(cat "${PID_FILE}")"
if kill -0 "${PID}" 2>/dev/null; then
  echo "Stopping REFLECTOR (PID ${PID})..."
  kill "${PID}"
  rm -f "${PID_FILE}"
else
  echo "Process ${PID} not running. Cleaning up PID file."
  rm -f "${PID_FILE}"
fi
