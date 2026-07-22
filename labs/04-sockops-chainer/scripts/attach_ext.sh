#!/usr/bin/env bash
set -euo pipefail

SLOT="${1:?usage: attach_ext.sh <slot> <ext-obj> <prog-name>}"
EXT_OBJ="${2:?usage: attach_ext.sh <slot> <ext-obj> <prog-name>}"
PROG_NAME="${3:?usage: attach_ext.sh <slot> <ext-obj> <prog-name>}"
CONTAINER="${CONTAINER:-c1}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab04_${CONTAINER}}"
CHAINCTL="${CHAINCTL:-build/chainctl}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "attach_ext.sh must run as root" >&2
  exit 1
fi

[[ -x "$CHAINCTL" ]] || {
  echo "missing chainctl: $CHAINCTL" >&2
  exit 1
}

[[ -f "$EXT_OBJ" ]] || {
  echo "missing extension object: $EXT_OBJ" >&2
  exit 1
}

"$CHAINCTL" attach-ext "$PIN_DIR" "$EXT_OBJ" "$PROG_NAME" "$SLOT"
