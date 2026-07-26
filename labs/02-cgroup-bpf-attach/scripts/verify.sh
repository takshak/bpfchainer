#!/usr/bin/env bash
set -euo pipefail

OBJ_PATH="${1:-build/cgroup_connect4.bpf.o}"
RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab2-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
TRACEFS_PATH="${TRACEFS_PATH:-/sys/kernel/tracing}"
PORT="${PORT:-45680}"
RESULT_LOG="$(mktemp)"
STATE_LOG="$(mktemp)"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$RESULT_LOG" "$STATE_LOG"
}
trap cleanup EXIT

need_cmd() {
  command -v "$1" >/dev/null || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

if [[ "$(id -u)" -ne 0 ]]; then
  echo "verify.sh must run as root" >&2
  exit 1
fi

need_cmd bpftool
need_cmd python3

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" ./scripts/load.sh "$OBJ_PATH"

echo "Attach state:"
bpftool cgroup show "$CGROUP_PATH"

set +e
"$RUNTIME" exec "$CONTAINER" python3 - "$PORT" >"$RESULT_LOG" 2>&1 <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(1)
try:
    sock.connect(("127.0.0.1", port))
    print("connect_result=SUCCESS")
except OSError as exc:
    print(f"connect_errno={exc.errno}")
    print(f"connect_error={exc}")
finally:
    sock.close()
PY
RESULT_STATUS=$?
set -e

echo "Connect result:"
cat "$RESULT_LOG"

if [[ "$RESULT_STATUS" -ne 0 ]]; then
  echo "container exec trigger failed" >&2
  exit 1
fi

CONTAINER="$CONTAINER" ./scripts/show_state.sh >"$STATE_LOG"
echo "BPF map state:"
cat "$STATE_LOG"

CONNECT_COUNT="$(awk -F= '$1 == "connect_count" { print $2 }' "$STATE_LOG")"
LAST_PORT="$(awk -F= '$1 == "last_port" { print $2 }' "$STATE_LOG")"

if [[ -z "$CONNECT_COUNT" || "$CONNECT_COUNT" -lt 1 ]]; then
  echo "expected connect_count >= 1" >&2
  exit 1
fi

if [[ "$LAST_PORT" != "$PORT" ]]; then
  echo "expected last_port=$PORT, got $LAST_PORT" >&2
  exit 1
fi

echo "Lab 02 verification passed"
echo "container=$CONTAINER"
echo "cgroup=$CGROUP_PATH"
