#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab04_${CONTAINER}}"
CHAINCTL="${CHAINCTL:-build/chainctl}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "reset_state.sh must run as root" >&2
  exit 1
fi

"$CHAINCTL" reset-state "$PIN_DIR"
