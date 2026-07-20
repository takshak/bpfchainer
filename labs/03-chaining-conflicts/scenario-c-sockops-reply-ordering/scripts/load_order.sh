#!/usr/bin/env bash
set -euo pipefail

ORDER="${1:?expected order: off-on or on-off}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_sock_ops}"
OFF_OBJ="${OFF_OBJ:-build/ecn_reply_off.bpf.o}"
ON_OBJ="${ON_OBJ:-build/ecn_reply_on.bpf.o}"
OFF_PIN="${OFF_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_off}"
ON_PIN="${ON_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_on}"

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

for obj in "$OFF_OBJ" "$ON_OBJ"; do
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

bpftool prog load "$OFF_OBJ" "$OFF_PIN" type sockops
bpftool prog load "$ON_OBJ" "$ON_PIN" type sockops

case "$ORDER" in
  off-on)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OFF_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ON_PIN" multi
    ;;
  on-off)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ON_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OFF_PIN" multi
    ;;
  *)
    echo "unknown order: $ORDER" >&2
    exit 1
    ;;
esac

echo "Attach state:"
bpftool cgroup show "$CGROUP_PATH"
