#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
DENY_MAP="${DENY_MAP:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_deny_maps/deny_state}"
ALLOW_MAP="${ALLOW_MAP:-/sys/fs/bpf/bpfchainer_lab03a_${CONTAINER}_allow_maps/allow_state}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "show_state.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

read_map() {
  local map_path="$1"
  local count_name="$2"
  local port_name="$3"

  [[ -e "$map_path" ]] || {
    echo "missing pinned map: $map_path" >&2
    exit 1
  }

  MAP_JSON="$(bpftool -j map dump pinned "$map_path")" \
  COUNT_NAME="$count_name" \
  PORT_NAME="$port_name" \
  python3 - <<'PY'
import json
import os

entries = json.loads(os.environ["MAP_JSON"])
count_name = os.environ["COUNT_NAME"]
port_name = os.environ["PORT_NAME"]

def to_int(raw):
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str):
        return int(raw, 0)
    raise TypeError(f"unsupported integer value: {raw!r}")

if not entries:
    print(f"{count_name}=0")
    print(f"{port_name}=0")
    raise SystemExit

value = entries[0]["value"]
if isinstance(value, dict):
    count = to_int(value[count_name])
    port = to_int(value["last_port"])
else:
    raw = [to_int(item) for item in value]
    count = int.from_bytes(bytes(raw[0:4]), "little")
    port = int.from_bytes(bytes(raw[4:8]), "little")

print(f"{count_name}={count}")
print(f"{port_name}={port}")
PY
}

read_map "$DENY_MAP" "deny_count" "deny_last_port"
read_map "$ALLOW_MAP" "allow_count" "allow_last_port"
