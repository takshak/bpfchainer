#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
ATTACH_TYPE="${ATTACH_TYPE:-cgroup_inet4_connect}"
DENY_PIN="${DENY_PIN:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_deny}"
ALLOW_PIN="${ALLOW_PIN:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_allow}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "unload.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

if [[ -d "$CGROUP_PATH" && -e "$ALLOW_PIN" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$ALLOW_PIN" 2>/dev/null || true
fi

if [[ -d "$CGROUP_PATH" && -e "$DENY_PIN" ]]; then
  bpftool cgroup detach "$CGROUP_PATH" "$ATTACH_TYPE" pinned "$DENY_PIN" 2>/dev/null || true
fi

rm -f "$ALLOW_PIN" "$DENY_PIN"
echo "Scenario A cleanup complete"
