#!/usr/bin/env bash
set -euo pipefail

EXPECTED_EVENTS="${1:-0}"
TIMEOUT_MS="${TIMEOUT_MS:-5000}"
CONTAINER="${CONTAINER:-c1}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
MONITOR="${MONITOR:-build/monitor}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "monitor.sh must run as root" >&2
  exit 1
fi

"$MONITOR" "$PIN_DIR" "$EXPECTED_EVENTS" "$TIMEOUT_MS"
