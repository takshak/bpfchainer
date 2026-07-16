#!/usr/bin/env bash
set -euo pipefail

OBJ_PATH="${1:-build/cgroup_connect4.bpf.o}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_PATH="${PIN_PATH:-/sys/fs/bpf/bpfchainer_lab02_${CONTAINER}_connect4}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"
PROG_TYPE="${PROG_TYPE:-cgroup/connect4}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "load.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

[[ -f "$OBJ_PATH" ]] || {
  echo "missing BPF object: $OBJ_PATH" >&2
  exit 1
}

[[ -d "$CGROUP_PATH" ]] || {
  echo "missing container cgroup: $CGROUP_PATH" >&2
  echo "create it first with: sudo ../01-container/container-runtime.sh create $CONTAINER" >&2
  exit 1
}

mkdir -p /sys/fs/bpf
if ! mountpoint -q /sys/fs/bpf; then
  mount -t bpf bpf /sys/fs/bpf
fi

if [[ -e "$PIN_PATH" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$PIN_PATH" 2>/dev/null || true
  rm -f "$PIN_PATH"
fi

bpftool prog load "$OBJ_PATH" "$PIN_PATH" type "$PROG_TYPE"
bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$PIN_PATH"

echo "Loaded $OBJ_PATH"
echo "Pinned at $PIN_PATH"
echo "Attached to $CGROUP_PATH as $ATTACH_TYPE"
