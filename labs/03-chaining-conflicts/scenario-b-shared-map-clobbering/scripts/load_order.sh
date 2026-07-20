#!/usr/bin/env bash
set -euo pipefail

ORDER="${1:?expected order: a-b or b-a}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"
A_OBJ="${A_OBJ:-build/writer_a.bpf.o}"
B_OBJ="${B_OBJ:-build/writer_b.bpf.o}"
A_PIN="${A_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_writer_a}"
B_PIN="${B_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_writer_b}"
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

for obj in "$A_OBJ" "$B_OBJ"; do
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

bpftool map create "$MAP_PIN" type array key 4 value 4 entries 1 name shared_values
bpftool map update pinned "$MAP_PIN" key 0 0 0 0 value 0 0 0 0 any

bpftool prog load "$A_OBJ" "$A_PIN" type cgroup/connect4 map name shared_values pinned "$MAP_PIN"
bpftool prog load "$B_OBJ" "$B_PIN" type cgroup/connect4 map name shared_values pinned "$MAP_PIN"

case "$ORDER" in
  a-b)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$A_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$B_PIN" multi
    ;;
  b-a)
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$B_PIN" multi
    bpftool cgroup attach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$A_PIN" multi
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
