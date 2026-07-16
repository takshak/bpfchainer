#!/bin/bash
set -euo pipefail

RUNTIME=${RUNTIME:-./container-runtime.sh}
NAME=${NAME:-lab1-verify-$$}
CG_ROOT=${CG_ROOT:-/sys/fs/cgroup/lab}
STATE_DIR=${STATE_DIR:-/run/containers}

cleanup() {
    "$RUNTIME" destroy "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "verify.sh must run as root" >&2
    exit 1
fi

for cmd in unshare nsenter pgrep sed; do
    command -v "$cmd" >/dev/null || {
        echo "missing required command: $cmd" >&2
        exit 1
    }
done

[[ -x "$RUNTIME" ]] || {
    echo "runtime is not executable: $RUNTIME" >&2
    exit 1
}

"$RUNTIME" create "$NAME"

PIDFILE="$STATE_DIR/$NAME.pid"
CGROUP="$CG_ROOT/$NAME"

[[ -f "$PIDFILE" ]] || {
    echo "missing pidfile: $PIDFILE" >&2
    exit 1
}

INIT_PID=$(cat "$PIDFILE")
kill -0 "$INIT_PID" 2>/dev/null || {
    echo "container init is not alive: $INIT_PID" >&2
    exit 1
}

[[ -d "$CGROUP" ]] || {
    echo "missing cgroup: $CGROUP" >&2
    exit 1
}

grep -qx "$INIT_PID" "$CGROUP/cgroup.procs" || {
    echo "container init is not in $CGROUP" >&2
    echo "expected pid: $INIT_PID" >&2
    echo "actual cgroup.procs:" >&2
    cat "$CGROUP/cgroup.procs" >&2
    exit 1
}

HOSTNAME_OUT=$("$RUNTIME" exec "$NAME" hostname)
[[ "$HOSTNAME_OUT" == "$NAME" ]] || {
    echo "unexpected hostname: $HOSTNAME_OUT" >&2
    exit 1
}

PID_OUT=$("$RUNTIME" exec "$NAME" bash -c 'echo $$')
[[ "$PID_OUT" -ne "$$" ]] || {
    echo "exec command did not enter a separate pid namespace" >&2
    exit 1
}

CGROUP_OUT=$("$RUNTIME" exec "$NAME" cat /proc/self/cgroup)
echo "$CGROUP_OUT" | grep -q "/lab/$NAME" || {
    echo "exec command did not join container cgroup" >&2
    echo "$CGROUP_OUT" >&2
    exit 1
}

echo "Lab 01 verification passed"
echo "container=$NAME"
echo "init_pid=$INIT_PID"
echo "cgroup=$CGROUP"
