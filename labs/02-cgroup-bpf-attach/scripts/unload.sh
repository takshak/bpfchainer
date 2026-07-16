#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_PATH="${PIN_PATH:-/sys/fs/bpf/bpfchainer_lab02_${CONTAINER}_connect4}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "unload.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

if [[ -e "$PIN_PATH" && -d "$CGROUP_PATH" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$PIN_PATH" 2>/dev/null || true
fi

if [[ -e "$PIN_PATH" ]]; then
  rm -f "$PIN_PATH"
  echo "Removed pinned program: $PIN_PATH"
fi

echo "Lab 02 cleanup complete"
echo "Container cgroup preserved: $CGROUP_PATH"
