#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_shared_values}"

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

if not entries:
    print("final_decision=0")
    print("last_writer=0")
    print("deny_count=0")
    print("allow_count=0")
    raise SystemExit

value = entries[0]["value"]
if isinstance(value, dict):
    print(f"final_decision={to_int(value['final_decision'])}")
    print(f"last_writer={to_int(value['last_writer'])}")
    print(f"deny_count={to_int(value['deny_count'])}")
    print(f"allow_count={to_int(value['allow_count'])}")
else:
    raw = [to_int(item) for item in value]
    print(f"final_decision={int.from_bytes(bytes(raw[0:4]), 'little')}")
    print(f"last_writer={int.from_bytes(bytes(raw[4:8]), 'little')}")
    print(f"deny_count={int.from_bytes(bytes(raw[8:12]), 'little')}")
    print(f"allow_count={int.from_bytes(bytes(raw[12:16]), 'little')}")
PY
