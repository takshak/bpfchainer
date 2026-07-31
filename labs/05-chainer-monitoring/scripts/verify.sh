#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab5-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
PORT="${PORT:-45682}"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "verify.sh must run as root" >&2
  exit 1
fi

for cmd in bpftool python3; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command: $cmd" >&2
    exit 1
  }
done

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

trigger_connection() {
  local server_log client_log
  server_log="$(mktemp)"
  client_log="$(mktemp)"

  "$RUNTIME" exec "$CONTAINER" python3 - "$PORT" >"$server_log" 2>&1 <<'PY' &
import socket
import sys

port = int(sys.argv[1])
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(1)
conn, _ = server.accept()
conn.recv(1)
conn.close()
server.close()
PY
  local server_pid=$!

  sleep 0.3

  "$RUNTIME" exec "$CONTAINER" python3 - "$PORT" >"$client_log" 2>&1 <<'PY'
import socket
import sys

port = int(sys.argv[1])
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.settimeout(2)
client.connect(("127.0.0.1", port))
client.send(b"x")
client.close()
PY

  wait "$server_pid"
  rm -f "$server_log" "$client_log"
}

read_state_value() {
  local key="$1"
  local state_file="$2"
  awk -F= -v key="$key" '$1 == key { print $2 }' "$state_file"
}

run_case() {
  local label="$1"
  local expected_events="$2"
  local attach_slot6="$3"
  local state_file monitor_log monitor_pid

  monitor_log="$(mktemp)"

  echo "== $label =="
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/unload.sh >/dev/null 2>&1 || true
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/load_chainer.sh
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 1 build/timeout_10.bpf.o timeout_10
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 2 build/timeout_20.bpf.o timeout_20
  if [[ "$attach_slot6" == "yes" ]]; then
    CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh 6 build/timeout_30.bpf.o timeout_30
  fi
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/reset_state.sh

  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" EXPECTED_EVENTS="$expected_events" ./scripts/monitor.sh "$expected_events" >"$monitor_log" 2>&1 &
  monitor_pid=$!

  sleep 0.2
  trigger_connection
  wait "$monitor_pid"

  echo "Monitor output:"
  cat "$monitor_log"

  state_file="$(mktemp)"
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/show_state.sh | tee "$state_file"
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/show_chain.sh

  local selected_priority selected_reply event_count event_lines
  selected_priority="$(read_state_value selected_priority "$state_file")"
  selected_reply="$(read_state_value selected_reply "$state_file")"
  event_count="$(read_state_value conflict_event_count "$state_file")"
  event_lines="$(grep -c '^EVENT ' "$monitor_log")"

  if [[ "$selected_priority" != "1" || "$selected_reply" != "10" ]]; then
    echo "unexpected selected result: priority=$selected_priority reply=$selected_reply" >&2
    exit 1
  fi

  if [[ "$event_count" != "$expected_events" || "$event_lines" != "$expected_events" ]]; then
    echo "expected $expected_events conflict events, state=$event_count monitor=$event_lines" >&2
    exit 1
  fi

  if [[ "$attach_slot6" == "yes" ]]; then
    grep -q 'conflict_slot=2 conflict_reply=20' "$monitor_log" || {
      echo "missing slot 2 conflict event" >&2
      exit 1
    }
    grep -q 'conflict_slot=6 conflict_reply=30' "$monitor_log" || {
      echo "missing slot 6 conflict event" >&2
      exit 1
    }
  else
    grep -q 'conflict_slot=2 conflict_reply=20' "$monitor_log" || {
      echo "missing slot 2 conflict event" >&2
      exit 1
    }
  fi

  rm -f "$state_file" "$monitor_log"
}

run_case "two writers: slot 1 wins, slot 2 conflicts" 1 no
run_case "three writers: slot 1 wins, slots 2 and 6 conflict" 2 yes

echo "Lab 5 verification passed"
