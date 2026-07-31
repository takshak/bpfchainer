#!/usr/bin/env bash
set -euo pipefail

CONTAINER="${CONTAINER:-c1}"
PIN_DIR="${PIN_DIR:-/sys/fs/bpf/bpfchainer_lab05_${CONTAINER}}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "show_chain.sh must run as root" >&2
  exit 1
fi

[[ -d "$PIN_DIR" ]] || {
  echo "missing pin dir: $PIN_DIR" >&2
  exit 1
}

echo "CHAIN:"
if [[ -e "$PIN_DIR/chainer_prog" ]]; then
  echo "  chainer:"
  bpftool prog show pinned "$PIN_DIR/chainer_prog" | sed 's/^/    /'
fi

for slot in 0 1 2 3 4 5 6; do
  prog_pin="$PIN_DIR/ext_prog_slot_$slot"
  link_pin="$PIN_DIR/ext_link_slot_$slot"
  if [[ -e "$prog_pin" ]]; then
    echo "  slot=$slot"
    echo "    program_pin=$prog_pin"
    [[ -e "$link_pin" ]] && echo "    link_pin=$link_pin"
    bpftool prog show pinned "$prog_pin" | sed 's/^/    /'
  fi
done
