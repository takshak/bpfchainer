# Scenario C — `sock_ops->reply` Ordering

This scenario shows that some cgroup-BPF hooks use mutable context fields, not
only return values, to communicate results back to the kernel.

Two `cgroup/sock_ops` programs attach to the same Lab 01 container cgroup with
`BPF_ALLOW_MULTI`.

The hook is `BPF_SOCK_OPS_NEEDS_ECN`. The kernel asks BPF whether the TCP
connection should request ECN during the handshake. Both programs receive the
same `struct bpf_sock_ops` context and write `skops->reply`:

- `ecn_reply_off` writes `skops->reply = 0`
- `ecn_reply_on` writes `skops->reply = 1`

Because the programs run in attach order and share the same context, the last
writer wins.

## Files

```text
src/ecn_reply_off.bpf.c   writes skops->reply = 0
src/ecn_reply_on.bpf.c    writes skops->reply = 1
scripts/load_order.sh     attaches off-on or on-off
scripts/unload.sh         detaches and unpins Scenario C programs
scripts/verify_order.sh   verifies ECN behavior with tcpdump
```

## One-command Verification

```bash
make all
sudo make verify
```

Expected behavior:

- `off-on`: final writer sets `reply=1`; tcpdump sees `Flags [SEW]`.
- `on-off`: final writer sets `reply=0`; tcpdump sees `Flags [S]`.

`tcpdump` shorthand:

- `S` means SYN.
- `E` means ECE.
- `W` means CWR.
- `Flags [SEW]` means the SYN requests ECN negotiation.

The verifier temporarily sets `net.ipv4.tcp_ecn=0` and restores the original
value on exit. That keeps the observed ECN bit tied to the BPF program instead
of the host default.

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

Expected order:

```text
ecn_reply_off
ecn_reply_on
```

Unload and reverse the order:

```bash
sudo CONTAINER=c1 make unload
sudo CONTAINER=c1 make load_off_last
sudo bpftool cgroup show /sys/fs/cgroup/lab/c1
```

Expected order:

```text
ecn_reply_on
ecn_reply_off
```

For packet-level ECN proof, prefer:

```bash
sudo make verify
```

That command handles the Python client/server, temporary `net.ipv4.tcp_ecn=0`,
tcpdump capture, and cleanup.

## Cleanup

Unload only Scenario C BPF state:

```bash
sudo CONTAINER=c1 make unload
```

This removes:

```text
/sys/fs/bpf/bpfchainer_lab03c_c1_ecn_off
/sys/fs/bpf/bpfchainer_lab03c_c1_ecn_on
```

It intentionally keeps `/sys/fs/cgroup/lab/c1` alive so you can run Scenario A
or B next.

When you are done with all scenarios, destroy the Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```

You may see several `bpf_printk` lines for one TCP connection. That is expected:
the kernel invokes `BPF_SOCK_OPS_NEEDS_ECN` at multiple handshake points on the
client and server paths. The verifier uses tcpdump's first SYN flags as the
primary signal.

## Requirements

- `tcpdump`
- `python3`
- `cubic` listed in `net.ipv4.tcp_available_congestion_control`
