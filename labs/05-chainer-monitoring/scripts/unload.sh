#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "unload.sh must run as root" >&2
  exit 1
fi

if [[ -d "$PIN_DIR" ]]; then
  rm -f "$PIN_DIR"/ext_link_slot_*
  if [[ -d "$CGROUP_PATH" && -e "$PIN_DIR/chainer_prog" ]]; then
    bpftool cgroup detach "$CGROUP_PATH" cgroup_sock_ops pinned "$PIN_DIR/chainer_prog" 2>/dev/null || true
  fi
  rm -f "$PIN_DIR"/ext_prog_slot_* "$PIN_DIR"/chainer_prog "$PIN_DIR"/state_map "$PIN_DIR"/events_map
  rmdir "$PIN_DIR" 2>/dev/null || true
fi

echo "Lab 5 cleanup complete"
