#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_sock_ops}"
OFF_PIN="${OFF_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_off}"
ON_PIN="${ON_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_ecn_on}"
OBSERVER_PIN="${OBSERVER_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_observer}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_sockops_state}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "unload.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

if [[ -d "$CGROUP_PATH" && -e "$OBSERVER_PIN" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OBSERVER_PIN" 2>/dev/null || true
fi

if [[ -d "$CGROUP_PATH" && -e "$OFF_PIN" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$OFF_PIN" 2>/dev/null || true
fi

if [[ -d "$CGROUP_PATH" && -e "$ON_PIN" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ON_PIN" 2>/dev/null || true
fi

rm -f "$OFF_PIN" "$ON_PIN" "$OBSERVER_PIN" "$MAP_PIN"
echo "Scenario C cleanup complete"
