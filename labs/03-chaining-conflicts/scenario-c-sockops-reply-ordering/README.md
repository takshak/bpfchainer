# Scenario C — `sock_ops->reply` Ordering

This scenario shows that some cgroup-BPF hooks use mutable context fields, not
only return values, to communicate results back to the kernel.

Three `cgroup/sock_ops` programs attach to the same Lab 01 container cgroup
with `BPF_ALLOW_MULTI`:

- `ecn_reply_off` writes `skops->reply = 0`
- `ecn_reply_on` writes `skops->reply = 1`
- `ecn_reply_observer` runs last and records the final `skops->reply`

The hook is `BPF_SOCK_OPS_NEEDS_ECN`. The kernel asks BPF whether the TCP
connection should request ECN during the handshake. Because the programs share
the same `struct bpf_sock_ops` context, the last writer controls the final
`reply` value.

The required verifier does not depend on kernel tracing or `tcpdump`.
Verification reads a pinned BPF map populated by the writer programs and the
observer program. An optional tcpdump demo is also provided to show the ECN bits
on the SYN packet when packet capture works in the VM.

## Orders

`off-on`:

```text
ecn_reply_off writes reply=0
ecn_reply_on writes reply=1
observer records final_reply=1
```

`on-off`:

```text
ecn_reply_on writes reply=1
ecn_reply_off writes reply=0
observer records final_reply=0
```

## Files

```text
src/ecn_reply_off.bpf.c       writes skops->reply = 0
src/ecn_reply_on.bpf.c        writes skops->reply = 1
src/ecn_reply_observer.bpf.c  records final skops->reply
scripts/load_order.sh         attaches off-on-observer or on-off-observer
scripts/show_state.sh         reads writer counts and final_reply
scripts/demo_tcpdump.sh       optional packet-level ECN demo
scripts/unload.sh             detaches and unpins Scenario C programs
scripts/verify_order.sh       verifies both orders through the shared map
```

## One-command Verification

```bash
make all
sudo make verify
```

Expected behavior:

```text
off-on:
  final_reply=1
  last_writer=2

on-off:
  final_reply=0
  last_writer=1
```

Both orders should show nonzero counts:

```text
off_count>0
on_count>0
observer_count>0
```

The verifier temporarily sets `net.ipv4.tcp_ecn=0` and restores the original
value on exit. That keeps the observed `reply` tied to the BPF programs instead
of the host default.

## Optional Tcpdump Demo

If the VM supports packet capture, run:

```bash
sudo make demo_tcpdump
```

Or run one order:

```bash
sudo make demo_tcpdump_on_last
sudo make demo_tcpdump_off_last
```

Expected packet-level behavior:

```text
off-on:  final writer sets reply=1; first SYN has Flags [SEW]
on-off:  final writer sets reply=0; first SYN has Flags [S]
```

`tcpdump` shorthand:

- `S` means SYN.
- `E` means ECE.
- `W` means CWR.
- `Flags [SEW]` means the SYN requests ECN negotiation.

The tcpdump demo is intentionally separate from `make verify` so the lab still
works on MicroVMs where packet capture is unavailable or restricted.

## Manual Attachment Demo With `c1`

Create a Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh create c1
```

Load `off-on`, where the final writer enables ECN:

```bash
cd ../03-chaining-conflicts/scenario-c-sockops-reply-ordering
make all
sudo CONTAINER=c1 make load_on_last
sudo bpftool cgroup show /sys/fs/cgroup/lab/c1
```

Trigger a TCP connection:

```bash
sudo ../../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 45678))
server.listen(1)

client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.connect(("127.0.0.1", 45678))

conn, _ = server.accept()
client.send(b"x")
conn.recv(1)

conn.close()
client.close()
server.close()
PY
```

Show the final observed reply:

```bash
sudo CONTAINER=c1 make show
```

Expected `off-on` map output includes:

```text
final_reply=1
last_writer=2
```

Unload and reverse the order:

```bash
sudo CONTAINER=c1 make unload
sudo CONTAINER=c1 make load_off_last
```

Trigger again and inspect:

```bash
sudo CONTAINER=c1 make show
```

Expected `on-off` map output includes:

```text
final_reply=0
last_writer=1
```

## Cleanup

Unload only Scenario C BPF state:

```bash
sudo CONTAINER=c1 make unload
```

This removes:

```text
/sys/fs/bpf/bpfchainer_lab03c_c1_ecn_off
/sys/fs/bpf/bpfchainer_lab03c_c1_ecn_on
/sys/fs/bpf/bpfchainer_lab03c_c1_observer
/sys/fs/bpf/bpfchainer_lab03c_c1_sockops_state
```

It intentionally keeps `/sys/fs/cgroup/lab/c1` alive so you can run Scenario A
or B next.

When you are done with all scenarios, destroy the Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```

## Requirements

- `python3`
- `cubic` listed in `net.ipv4.tcp_available_congestion_control`
- Optional: `tcpdump` for `make demo_tcpdump`
