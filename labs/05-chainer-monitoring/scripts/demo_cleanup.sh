#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
DESTROY_CONTAINER="${DESTROY_CONTAINER:-1}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "demo_cleanup.sh must run as root" >&2
  exit 1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/unload.sh

if [[ "$DESTROY_CONTAINER" == "1" ]]; then
  [[ -x "$RUNTIME" ]] || {
    echo "missing executable Lab 1 runtime: $RUNTIME" >&2
    exit 1
  }
  "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  echo "container '$CONTAINER' destroyed"
else
  echo "container '$CONTAINER' preserved because DESTROY_CONTAINER=$DESTROY_CONTAINER"
fi
