#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"
DENY_OBJ="${DENY_OBJ:-build/deny_connect4.bpf.o}"
ALLOW_OBJ="${ALLOW_OBJ:-build/allow_connect4.bpf.o}"
DENY_PIN="${DENY_PIN:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_deny}"
ALLOW_PIN="${ALLOW_PIN:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_allow}"
DENY_MAP_DIR="${DENY_MAP_DIR:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_deny_maps}"
ALLOW_MAP_DIR="${ALLOW_MAP_DIR:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_allow_maps}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "load_multi.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

[[ -d "$CGROUP_PATH" ]] || {
  echo "missing container cgroup: $CGROUP_PATH" >&2
  exit 1
}

for obj in "$DENY_OBJ" "$ALLOW_OBJ"; do
  [[ -f "$obj" ]] || {
    echo "missing BPF object: $obj" >&2
    exit 1
  }
done

./scripts/unload.sh >/dev/null 2>&1 || true

mkdir -p /sys/fs/bpf
if ! mountpoint -q /sys/fs/bpf; then
  mount -t bpf bpf /sys/fs/bpf
fi

rm -rf "$DENY_MAP_DIR" "$ALLOW_MAP_DIR"
mkdir -p "$DENY_MAP_DIR" "$ALLOW_MAP_DIR"

bpftool prog load "$DENY_OBJ" "$DENY_PIN" type cgroup/connect4 pinmaps "$DENY_MAP_DIR"
bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$DENY_PIN" multi

bpftool prog load "$ALLOW_OBJ" "$ALLOW_PIN" type cgroup/connect4 pinmaps "$ALLOW_MAP_DIR"
bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ALLOW_PIN" multi

echo "Attached with BPF_ALLOW_MULTI semantics in order:"
echo "1. deny_connect4 -> $DENY_PIN"
echo "2. allow_connect4 -> $ALLOW_PIN"
echo "deny maps: $DENY_MAP_DIR"
echo "allow maps: $ALLOW_MAP_DIR"
echo "cgroup: $CGROUP_PATH"
