#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab3a-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
TRACEFS_PATH="${TRACEFS_PATH:-/sys/kernel/tracing}"
TRACE_LOG="$(mktemp)"
RESULT_LOG="$(mktemp)"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$TRACE_LOG" "$RESULT_LOG"
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "verify.sh must run as root" >&2
  exit 1
fi

for cmd in bpftool python3 timeout; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

[[ -d "$TRACEFS_PATH" ]] || {
  echo "missing tracefs path: $TRACEFS_PATH" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" ./scripts/load_multi.sh

echo "Attach state:"
bpftool cgroup show "$CGROUP_PATH"

: > "$TRACEFS_PATH/trace"
timeout 5 cat "$TRACEFS_PATH/trace_pipe" >"$TRACE_LOG" 2>&1 &
TRACE_PID=$!
sleep 1

set +e
"$RUNTIME" exec "$CONTAINER" python3 - <<'PY' >"$RESULT_LOG" 2>&1
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(1)
try:
    sock.connect(("127.0.0.1", 1))
    print("connect_result=SUCCESS")
except OSError as exc:
    print(f"connect_errno={exc.errno}")
    print(f"connect_error={exc}")
finally:
    sock.close()
PY
RESULT_STATUS=$?
wait "$TRACE_PID"
TRACE_STATUS=$?
set -e

echo "Connect result:"
cat "$RESULT_LOG"
echo "Trace output:"
cat "$TRACE_LOG"

[[ "$RESULT_STATUS" -eq 0 ]] || {
  echo "container exec trigger failed" >&2
  exit 1
}

[[ "$TRACE_STATUS" -eq 0 || "$TRACE_STATUS" -eq 124 ]] || {
  echo "failed to read trace output" >&2
  exit 1
}

grep -q "scenario_a deny port=1 return=DENY" "$TRACE_LOG" || {
  echo "deny program did not run" >&2
  exit 1
}

grep -q "scenario_a allow port=1 return=ALLOW" "$TRACE_LOG" || {
  echo "allow program did not run" >&2
  exit 1
}

grep -q "connect_errno=1" "$RESULT_LOG" || {
  echo "expected sticky deny result EPERM/connect_errno=1" >&2
  exit 1
}

echo "Scenario A verification passed"
echo "container=$CONTAINER"
echo "cgroup=$CGROUP_PATH"
