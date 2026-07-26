#!/usr/bin/env bash
set -euo pipefail

ORDER="${1:?expected order: off-on or on-off}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_sock_ops}"
OFF_OBJ="${OFF_OBJ:-build/ecn_reply_off.bpf.o}"
ON_OBJ="${ON_OBJ:-build/ecn_reply_on.bpf.o}"
OBSERVER_OBJ="${OBSERVER_OBJ:-build/ecn_reply_observer.bpf.o}"
OFF_PIN="${OFF_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_off}"
ON_PIN="${ON_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_on}"
OBSERVER_PIN="${OBSERVER_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_observer}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_sockops_state}"

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

for obj in "$OFF_OBJ" "$ON_OBJ" "$OBSERVER_OBJ"; do
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

bpftool map create "$MAP_PIN" type array key 4 value 24 entries 1 name sockops_state
bpftool map update pinned "$MAP_PIN" key 0 0 0 0 value 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 any

bpftool prog load "$OFF_OBJ" "$OFF_PIN" type sockops map name sockops_state pinned "$MAP_PIN"
bpftool prog load "$ON_OBJ" "$ON_PIN" type sockops map name sockops_state pinned "$MAP_PIN"
bpftool prog load "$OBSERVER_OBJ" "$OBSERVER_PIN" type sockops map name sockops_state pinned "$MAP_PIN"

case "$ORDER" in
  off-on)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OFF_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ON_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OBSERVER_PIN" multi
    ;;
  on-off)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ON_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OFF_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OBSERVER_PIN" multi
    ;;
  *)
    echo "unknown order: $ORDER" >&2
    exit 1
    ;;
esac

echo "Attach state:"
bpftool cgroup show "$CGROUP_PATH"
echo "Shared map:"
bpftool map show pinned "$MAP_PIN"
