#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab3b-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03b_${CONTAINER}_shared_values}"
PORT="${PORT:-45679}"
RESULT_LOG="$(mktemp)"
STATE_LOG="$(mktemp)"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$RESULT_LOG" "$STATE_LOG"
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "verify_order.sh must run as root" >&2
  exit 1
fi

for cmd in bpftool python3; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

EXPECT_FINAL_DECISION=1
EXPECT_LAST_WRITER=1

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/load_order.sh

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

CONTAINER="$CONTAINER" MAP_PIN="$MAP_PIN" ./scripts/show_state.sh >"$STATE_LOG"
ACTUAL_FINAL_DECISION="$(awk -F= '$1 == "final_decision" { print $2 }' "$STATE_LOG")"
ACTUAL_LAST_WRITER="$(awk -F= '$1 == "last_writer" { print $2 }' "$STATE_LOG")"
DENY_COUNT="$(awk -F= '$1 == "deny_count" { print $2 }' "$STATE_LOG")"
ALLOW_COUNT="$(awk -F= '$1 == "allow_count" { print $2 }' "$STATE_LOG")"

echo "Connect result:"
cat "$RESULT_LOG"
echo "BPF map state:"
cat "$STATE_LOG"
echo "expected_connection_errno=1"
echo "expected_final_decision=$EXPECT_FINAL_DECISION"
echo "actual_final_decision=$ACTUAL_FINAL_DECISION"

[[ "$RESULT_STATUS" -eq 0 ]] || {
  echo "container exec trigger failed" >&2
  exit 1
}

grep -q "connect_errno=1" "$RESULT_LOG" || {
  echo "expected denied connection with EPERM/connect_errno=1" >&2
  exit 1
}

if [[ "$DENY_COUNT" != "1" || "$ALLOW_COUNT" != "1" ]]; then
  echo "expected deny and allow writers to run exactly once" >&2
  exit 1
fi

if [[ "$ACTUAL_LAST_WRITER" -ne "$EXPECT_LAST_WRITER" ]]; then
  echo "unexpected last_writer" >&2
  exit 1
fi

if [[ "$ACTUAL_FINAL_DECISION" -ne "$EXPECT_FINAL_DECISION" ]]; then
  echo "unexpected final_decision" >&2
  exit 1
fi

echo "Scenario B verification passed"
echo "container=$CONTAINER"
echo "cgroup=$CGROUP_PATH"
