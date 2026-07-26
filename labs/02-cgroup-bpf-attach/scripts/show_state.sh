#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab02_${CONTAINER}_maps/connect4_state}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "show_state.sh must run as root" >&2
  exit 1
fi

command -v bpftool >/dev/null || {
  echo "bpftool is required" >&2
  exit 1
}

[[ -e "$MAP_PIN" ]] || {
  echo "missing pinned map: $MAP_PIN" >&2
  exit 1
}

STATE_JSON="$(bpftool -j map dump pinned "$MAP_PIN")"

STATE_JSON="$STATE_JSON" python3 - <<'PY'
import json
import os
import sys

entries = json.loads(os.environ["STATE_JSON"])
if not entries:
    print("connect_count=0")
    print("last_port=0")
    sys.exit(0)

value = entries[0]["value"]

def to_int(raw):
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str):
        return int(raw, 0)
    raise TypeError(f"unsupported integer value: {raw!r}")

if isinstance(value, dict):
    print(f"connect_count={to_int(value['connect_count'])}")
    print(f"last_port={to_int(value['last_port'])}")
else:
    raw = [to_int(item) for item in value]
    connect_count = int.from_bytes(bytes(raw[0:4]), "little")
    last_port = int.from_bytes(bytes(raw[4:8]), "little")
    print(f"connect_count={connect_count}")
    print(f"last_port={last_port}")
PY
