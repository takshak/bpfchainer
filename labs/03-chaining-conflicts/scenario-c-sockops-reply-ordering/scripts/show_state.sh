#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_sockops_state}"

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

MAP_JSON="$(bpftool -j map dump pinned "$MAP_PIN")"

MAP_JSON="$MAP_JSON" python3 - <<'PY'
import json
import os

entries = json.loads(os.environ["MAP_JSON"])

def to_int(raw):
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str):
        return int(raw, 0)
    raise TypeError(f"unsupported integer value: {raw!r}")

fields = [
    "needs_ecn_calls",
    "off_count",
    "on_count",
    "observer_count",
    "final_reply",
    "last_writer",
]

if not entries:
    for field in fields:
        print(f"{field}=0")
    raise SystemExit

value = entries[0]["value"]
if isinstance(value, dict):
    for field in fields:
        print(f"{field}={to_int(value[field])}")
else:
    raw = [to_int(item) for item in value]
    for idx, field in enumerate(fields):
        start = idx * 4
        print(f"{field}={int.from_bytes(bytes(raw[start:start + 4]), 'little')}")
PY
