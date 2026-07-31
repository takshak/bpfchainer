#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-c1}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"
PORT="${PORT:-45682}"
EXPECTED_EVENTS="${EXPECTED_EVENTS:-2}"
TIMEOUT_MS="${TIMEOUT_MS:-5000}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "demo_traffic.sh must run as root" >&2
  exit 1
fi

[[ -x "$RUNTIME" ]] || {
  echo "missing executable Lab 1 runtime: $RUNTIME" >&2
  exit 1
}

[[ -d "$CGROUP_PATH" ]] || {
  echo "missing container cgroup: $CGROUP_PATH" >&2
  echo "run: sudo make -f Makefile.setup" >&2
  exit 1
}

[[ -d "$PIN_DIR" ]] || {
  echo "missing Lab 5 pin directory: $PIN_DIR" >&2
  echo "run: sudo make -f Makefile.setup" >&2
  exit 1
}

server_log="$(mktemp)"
client_log="$(mktemp)"
monitor_log="$(mktemp)"
server_pid=""
monitor_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$monitor_pid" ]]; then
    kill "$monitor_pid" >/dev/null 2>&1 || true
    wait "$monitor_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$server_log" "$client_log" "$monitor_log"
}
trap cleanup EXIT

CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/reset_state.sh

CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" EXPECTED_EVENTS="$EXPECTED_EVENTS" TIMEOUT_MS="$TIMEOUT_MS" \
  ./scripts/monitor.sh "$EXPECTED_EVENTS" >"$monitor_log" 2>&1 &
monitor_pid=$!

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
server_pid=$!

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
wait "$monitor_pid"

echo "Ringbuf monitor output:"
cat "$monitor_log"

echo
echo "Map state after traffic:"
CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" PIN_DIR="$PIN_DIR" ./scripts/show_state.sh

echo
echo "Chainer programs and links:"
CONTAINER="$CONTAINER" PIN_DIR="$PIN_DIR" ./scripts/show_chain.sh
