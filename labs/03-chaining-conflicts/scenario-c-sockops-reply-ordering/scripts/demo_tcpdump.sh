#!/usr/bin/env bash
set -euo pipefail

ORDER="${1:?expected order: off-on or on-off}"
RUNTIME="${RUNTIME:-../../01-container/container-runtime.sh}"
CONTAINER="${CONTAINER:-lab3c-tcpdump-$$}"
CGROUP_PATH="${CGROUP_PATH:-/sys/fs/cgroup/lab/$CONTAINER}"
MAP_PIN="${MAP_PIN:-/sys/fs/bpf/bpfchainer_lab03c_${CONTAINER}_sockops_state}"
PORT="${PORT:-45678}"
TCPDUMP_LOG="$(mktemp)"
SERVER_LOG="$(mktemp)"
CLIENT_LOG="$(mktemp)"
STATE_LOG="$(mktemp)"
ORIGINAL_TCP_ECN=""
OWN_CONTAINER=0

cleanup() {
  if [[ -n "$ORIGINAL_TCP_ECN" ]]; then
    sysctl -q -w "net.ipv4.tcp_ecn=$ORIGINAL_TCP_ECN" >/dev/null 2>&1 || true
  fi
  CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/unload.sh >/dev/null 2>&1 || true
  if [[ "$OWN_CONTAINER" -eq 1 ]]; then
    "$RUNTIME" destroy "$CONTAINER" >/dev/null 2>&1 || true
  fi
  rm -f "$TCPDUMP_LOG" "$SERVER_LOG" "$CLIENT_LOG" "$STATE_LOG"
}
trap cleanup EXIT

if [[ "$(id -u)" -ne 0 ]]; then
  echo "demo_tcpdump.sh must run as root" >&2
  exit 1
fi

for cmd in bpftool python3 sysctl tcpdump timeout; do
  command -v "$cmd" >/dev/null || {
    echo "missing required command for optional tcpdump demo: $cmd" >&2
    exit 1
  }
done

case "$ORDER" in
  off-on)
    EXPECT_ECN=1
    ;;
  on-off)
    EXPECT_ECN=0
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

if ! sysctl -n net.ipv4.tcp_available_congestion_control | grep -qw cubic; then
  echo "cubic congestion control is required for this demo" >&2
  exit 1
fi

ORIGINAL_TCP_ECN="$(sysctl -n net.ipv4.tcp_ecn)"
sysctl -q -w net.ipv4.tcp_ecn=0 >/dev/null

if [[ ! -d "$CGROUP_PATH" ]]; then
  "$RUNTIME" create "$CONTAINER"
  OWN_CONTAINER=1
fi

CONTAINER="$CONTAINER" CGROUP_PATH="$CGROUP_PATH" MAP_PIN="$MAP_PIN" ./scripts/load_order.sh "$ORDER"

timeout 6 tcpdump -i lo -nnvvv -c 4 "tcp and port $PORT" >"$TCPDUMP_LOG" 2>&1 &
TCPDUMP_PID=$!

sleep 1

"$RUNTIME" exec "$CONTAINER" python3 - "$PORT" >"$SERVER_LOG" 2>&1 <<'PY' &
import socket
import sys

port = int(sys.argv[1])
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.setsockopt(socket.IPPROTO_TCP, socket.TCP_CONGESTION, b"cubic")
server.bind(("127.0.0.1", port))
server.listen(1)
conn, _ = server.accept()
conn.recv(1)
conn.close()
server.close()
PY
SERVER_PID=$!

sleep 0.4

"$RUNTIME" exec "$CONTAINER" python3 - "$PORT" >"$CLIENT_LOG" 2>&1 <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.setsockopt(socket.IPPROTO_TCP, socket.TCP_CONGESTION, b"cubic")
client.settimeout(2)
client.connect(("127.0.0.1", port))
cc = client.getsockopt(socket.IPPROTO_TCP, socket.TCP_CONGESTION, 32)
print("client_cc=" + cc.rstrip(b"\x00").decode("ascii", "replace"))
client.send(b"x")
time.sleep(0.2)
client.close()
PY

wait "$SERVER_PID"
wait "$TCPDUMP_PID" || true

CONTAINER="$CONTAINER" MAP_PIN="$MAP_PIN" ./scripts/show_state.sh >"$STATE_LOG"

FIRST_SYN_FLAGS="$(
  awk '
    /Flags \[/ {
      flags = $0
      sub(/^.*Flags \[/, "", flags)
      sub(/\].*$/, "", flags)
      if (index(flags, "S") > 0) {
        print flags
        exit
      }
    }
  ' "$TCPDUMP_LOG"
)"

if [[ "$FIRST_SYN_FLAGS" == *E* && "$FIRST_SYN_FLAGS" == *W* ]]; then
  SEEN_ECN=1
else
  SEEN_ECN=0
fi

echo "Client output:"
cat "$CLIENT_LOG"
echo "BPF map state:"
cat "$STATE_LOG"
echo "Tcpdump output:"
cat "$TCPDUMP_LOG"
echo "expected_ecn=$EXPECT_ECN"
echo "seen_ecn=$SEEN_ECN"
echo "first_syn_flags=${FIRST_SYN_FLAGS:-missing}"

if [[ "$SEEN_ECN" -ne "$EXPECT_ECN" ]]; then
  echo "unexpected ECN SYN flags for order $ORDER" >&2
  exit 1
fi

echo "Scenario C tcpdump demo passed for $ORDER"
