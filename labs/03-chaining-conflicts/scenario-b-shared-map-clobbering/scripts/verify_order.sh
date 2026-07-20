#!/usr/bin/env bash
set -euo pipefail

ORDER="${1:?expected order: a-b or b-a}"
RUNTIME="${RUNTIME:-../../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab3b-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_shared_values}"
TRACEFS_PATH="${TRACEFS_PATH:-/sys/kernel/tracing}"
PORT="${PORT:-45679}"
TRACE_LOG="$(mktemp)"
RESULT_LOG="$(mktemp)"
MAP_JSON="$(mktemp)"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$TRACE_LOG" "$RESULT_LOG" "$MAP_JSON"
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "verify_order.sh must run as root" >&2
  exit 1
fi

for cmd in bpftool python3 timeout; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

case "$ORDER" in
  a-b)
    EXPECT_VALUE=11
    EXPECT_WRITER="writer_b"
    ;;
  b-a)
    EXPECT_VALUE=10
    EXPECT_WRITER="writer_a"
    ;;
  *)
    echo "unknown order: $ORDER" >&2
    exit 1
    ;;
esac

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/load_order.sh "$ORDER"

: > "$TRACEFS_PATH/trace"
timeout 5 cat "$TRACEFS_PATH/trace_pipe" >"$TRACE_LOG" 2>&1 &
TRACE_PID=$!

sleep 1

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
wait "$TRACE_PID"
TRACE_STATUS=$?
set -e

bpftool -j map dump pinned "$MAP_PIN" >"$MAP_JSON"
ACTUAL_VALUE="$(python3 - "$MAP_JSON" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

if not data:
    raise SystemExit("map dump is empty")

value = data[0]["value"]
raw = bytes(int(byte, 16) if isinstance(byte, str) else int(byte) for byte in value)
print(int.from_bytes(raw, "little"))
PY
)"

echo "Connect result:"
cat "$RESULT_LOG"
echo "Trace output:"
cat "$TRACE_LOG"
echo "Map dump:"
cat "$MAP_JSON"
echo "expected_final_writer=$EXPECT_WRITER"
echo "expected_final_value=$EXPECT_VALUE"
echo "actual_final_value=$ACTUAL_VALUE"

[[ "$RESULT_STATUS" -eq 0 ]] || {
  echo "container exec trigger failed" >&2
  exit 1
}

[[ "$TRACE_STATUS" -eq 0 || "$TRACE_STATUS" -eq 124 ]] || {
  echo "failed to read trace output" >&2
  exit 1
}

grep -q "scenario_b writer_a" "$TRACE_LOG" || {
  echo "writer_a did not run" >&2
  exit 1
}

grep -q "scenario_b writer_b" "$TRACE_LOG" || {
  echo "writer_b did not run" >&2
  exit 1
}

if [[ "$ACTUAL_VALUE" -ne "$EXPECT_VALUE" ]]; then
  echo "unexpected final map value for order $ORDER" >&2
  exit 1
fi

echo "Scenario B verification passed for $ORDER"
echo "container=$CONTAINER"
echo "cgroup=$CGROUP_PATH"
