#!/bin/bash
# container-runtime.sh — a tiny container runtime, built step by step.
#
# Iteration: create / enter / destroy. Host networking.
# Default init: sleep infinity.
#
# Usage:
#   ./container-runtime.sh create  <name>
#   ./container-runtime.sh enter   <name>
#   ./container-runtime.sh destroy <name>
#
# What "create" does:
#   1. make a cgroup slice for the container   (/sys/fs/cgroup/lab/<name>)
#   2. put ourselves into that slice           (children inherit it)
#   3. unshare pid+mount+uts namespaces, set hostname, mount fresh /proc,
#      and start the container's init process: sleep infinity
#
# The container is just that process, wearing isolation.

set -euo pipefail

STATE_DIR=/run/containers
CG_ROOT=/sys/fs/cgroup/lab

create_cgroup() {
    local name=$1
    mkdir -p "$CG_ROOT/$name"
    # Move the current shell (this script) into the slice.
    # Everything we start from here on — including the container's
    # init — inherits this cgroup membership.
    echo $$ > "$CG_ROOT/$name/cgroup.procs"
}

start_container() {
    local name=$1
    mkdir -p "$STATE_DIR"
    # New pid + mount + uts namespaces.
    #   --fork       : the command runs as a child => it becomes PID 1
    #   --mount-proc : mount a fresh /proc scoped to the new pid ns,
    #                  so `ps` inside shows only container processes
    unshare --pid --mount --uts --fork --mount-proc \
        bash -c "hostname $name; exec sleep infinity" &
    local parent=$!

    # The pidfile must hold the CHILD (the container's init — PID 1
    # inside the new namespace), NOT the unshare parent. The parent
    # never joins the new pid namespace; pid namespaces only apply
    # to children. Recording the parent breaks `enter` (nsenter -p
    # would join the host pid ns) and breaks `destroy` (killing the
    # parent orphans the init instead of stopping the container).
    # Retry briefly; fail loudly rather than record the wrong PID.
    local child=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        child=$(pgrep -P "$parent" | head -1) || true
        [[ -n $child ]] && break
        sleep 0.1
    done
    [[ -n $child ]] || { echo "failed to find container init" >&2; exit 1; }

    echo "$child" > "$STATE_DIR/$name.pid"
    echo "container '$name' started, init pid (host view): $child"
}

enter_container() {
    local name=${1:?usage: $0 enter <name>}
    local pidfile="$STATE_DIR/$name.pid"

    [[ -f $pidfile ]] || { echo "no such container: $name" >&2; exit 1; }
    local pid; pid=$(cat "$pidfile")

    kill -0 "$pid" 2>/dev/null || { echo "container '$name' is dead" >&2; exit 1; }

    # Join the container's cgroup BEFORE entering its namespaces.
    # nsenter joins namespaces, NOT cgroups — without this line, a
    # shell "inside" the container would send traffic that bypasses
    # every BPF program attached to the container's cgroup slice.
    echo $$ > "$CG_ROOT/$name/cgroup.procs"

    # Join pid + mount + uts namespaces and drop into a shell.
    # No /proc remount needed: with the correct target PID, the
    # container's mount namespace already has the right /proc
    # (mounted by --mount-proc at create time).
    exec nsenter -t "$pid" -p -m -u bash
}

destroy_container() {
    local name=${1:?usage: $0 destroy <name>}
    local pidfile="$STATE_DIR/$name.pid"

    [[ -f $pidfile ]] || { echo "no such container: $name" >&2; exit 1; }

    # cgroup v2 kill switch: SIGKILLs every process in the cgroup,
    # atomically. Works even if the pidfile is stale or wrong —
    # the cgroup, not a PID, is the container's real identity.
    echo 1 > "$CG_ROOT/$name/cgroup.kill"

    rm -f "$pidfile"

    # rmdir only works on an EMPTY cgroup, and the kernel reaps the
    # killed processes asynchronously — brief retry loop.
    for _ in 1 2 3 4 5; do
        rmdir "$CG_ROOT/$name" 2>/dev/null && break
        sleep 0.2
    done

    if [[ -d "$CG_ROOT/$name" ]]; then
        echo "warning: cgroup $CG_ROOT/$name not empty yet:" >&2
        cat "$CG_ROOT/$name/cgroup.procs" >&2
    else
        echo "container '$name' destroyed"
    fi
}

main() {
    local cmd=${1:-}
    case "$cmd" in
        create)
            local name=${2:?usage: $0 create <name>}
            create_cgroup "$name"
            start_container "$name"
            ;;
        enter)
            local name=${2:?usage: $0 enter <name>}
            enter_container "$name"
            ;;
        destroy)
            local name=${2:?usage: $0 destroy <name>}
            destroy_container "$name"
            ;;
        *)
            echo "usage: $0 {create|enter|destroy} <name>" >&2
            exit 1
            ;;
    esac
}

main "$@"
