#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
CHAINER_OBJ="${CHAINER_OBJ:-build/monitored_chainer.bpf.o}"
CHAINCTL="${CHAINCTL:-build/chainctl}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "load_chainer.sh must run as root" >&2
  exit 1
fi

[[ -d "$CGROUP_PATH" ]] || {
  echo "missing container cgroup: $CGROUP_PATH" >&2
  exit 1
}

[[ -f "$CHAINER_OBJ" ]] || {
  echo "missing chainer object: $CHAINER_OBJ" >&2
  exit 1
}

[[ -x "$CHAINCTL" ]] || {
  echo "missing chainctl: $CHAINCTL" >&2
  exit 1
}

mkdir -p /sys/fs/bpf
if ! mountpoint -q /sys/fs/bpf; then
  mount -t bpf bpf /sys/fs/bpf
fi

"$(dirname "$0")/unload.sh" >/dev/null 2>&1 || true
mkdir -p "$PIN_DIR"

"$CHAINCTL" load-chainer "$CGROUP_PATH" "$CHAINER_OBJ" "$PIN_DIR"
bpftool cgroup show "$CGROUP_PATH"
