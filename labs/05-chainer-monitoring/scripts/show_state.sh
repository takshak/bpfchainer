#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
CHAINCTL="${CHAINCTL:-build/chainctl}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "show_state.sh must run as root" >&2
  exit 1
fi

"$CHAINCTL" show-state "$PIN_DIR"

if [[ -d "$CGROUP_PATH" ]]; then
  echo "attached_programs:"
  bpftool cgroup show "$CGROUP_PATH" || true
fi
