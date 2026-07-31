#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "demo_setup.sh must run as root" >&2
  exit 1
fi

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
else
  echo "container '$CONTAINER' already exists, reusing $CGROUP_PATH"
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/load_chainer.sh
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 1 build/timeout_10.bpf.o timeout_10
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 2 build/timeout_20.bpf.o timeout_20
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 6 build/timeout_30.bpf.o timeout_30
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/reset_state.sh

echo
echo "Chainer programs and links:"
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/show_chain.sh

echo
echo "Initial map state:"
CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/show_state.sh
