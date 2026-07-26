#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"
DENY_OBJ="${DENY_OBJ:-build/deny_writer.bpf.o}"
ALLOW_OBJ="${ALLOW_OBJ:-build/allow_writer.bpf.o}"
DENY_PIN="${DENY_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_deny_writer}"
ALLOW_PIN="${ALLOW_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_allow_writer}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_shared_values}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "load_order.sh must run as root" >&2
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

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" ./scripts/unload.sh >/dev/null 2>&1 || true

mkdir -p /sys/fs/bpf
if ! mountpoint -q /sys/fs/bpf; then
  mount -t bpf bpf /sys/fs/bpf
fi

bpftool map create "$MAP_PIN" type array key 4 value 16 entries 1 name shared_values
bpftool map update pinned "$MAP_PIN" key 0 0 0 0 value 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 any

bpftool prog load "$DENY_OBJ" "$DENY_PIN" type cgroup/connect4 map name shared_values pinned "$MAP_PIN"
bpftool prog load "$ALLOW_OBJ" "$ALLOW_PIN" type cgroup/connect4 map name shared_values pinned "$MAP_PIN"

bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$DENY_PIN" multi
bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ALLOW_PIN" multi

echo "Attach state:"
bpftool cgroup show "$CGROUP_PATH"
echo "Shared map:"
bpftool map show pinned "$MAP_PIN"
