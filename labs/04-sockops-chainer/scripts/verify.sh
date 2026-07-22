#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab4-verify-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab04_${CONTAINER}}"
CHAINCTL="${CHAINCTL:-build/chainctl}"
PORT="${PORT:-45681}"
OWN_CONTAINER=0

cleanup() {
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
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
  local first_slot="$2"
  local first_obj="$3"
  local first_prog="$4"
  local second_slot="$5"
  local second_obj="$6"
  local second_prog="$7"
  local state_file

  echo "== $label =="
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/unload.sh >/dev/null 2>&1 || true
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/load_chainer.sh
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh "$first_slot" "$first_obj" "$first_prog"
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/attach_ext.sh "$second_slot" "$second_obj" "$second_prog"
  CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/reset_state.sh

  trigger_connection

  state_file="$(mktemp)"
  "$CHAINCTL" show-state "$PIN_DIR" | tee "$state_file"

  local selected_priority selected_reply writer_count double_writer_count
  selected_priority="$(read_state_value selected_priority "$state_file")"
  selected_reply="$(read_state_value selected_reply "$state_file")"
  writer_count="$(read_state_value writer_count "$state_file")"
  double_writer_count="$(read_state_value double_writer_count "$state_file")"
  rm -f "$state_file"

  if [[ "$selected_priority" != "1" || "$selected_reply" != "10" ]]; then
    echo "unexpected selected result: priority=$selected_priority reply=$selected_reply" >&2
    exit 1
  fi

  if [[ "$writer_count" -lt 2 || "$double_writer_count" -lt 1 ]]; then
    echo "expected both writers and at least one double-writer event" >&2
    echo "writer_count=$writer_count double_writer_count=$double_writer_count" >&2
    exit 1
  fi
}

run_case "load high priority number first, lower priority number second" \
  2 build/timeout_20.bpf.o timeout_20 \
  1 build/timeout_10.bpf.o timeout_10

run_case "load lower priority number first, high priority number second" \
  1 build/timeout_10.bpf.o timeout_10 \
  2 build/timeout_20.bpf.o timeout_20

echo "Lab 4 verification passed"
echo "priority_slot_1_reply=10"
echo "priority_slot_2_reply=20"
