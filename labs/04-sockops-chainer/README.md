# Exercise 04 — A Production-Style Sockops Chainer

Lab 03 showed that multiple `cgroup/sock_ops` programs can conflict when they
write the same mutable context field, such as `skops->reply`. This lab replaces
attach-order behavior with a small, deterministic chainer modeled after the
production sockops chainer.

The tutorial version keeps the production idea but removes the macro machinery:

```text
Lab 1 container cgroup
  |
  +-- one attached sockops_chainer program
        |
        +-- chain_slot_0()
        +-- chain_slot_1()  <- freplace extension can replace this
        +-- chain_slot_2()  <- freplace extension can replace this
        +-- chain_slot_3()
```

The chainer calls slots in numeric priority order. Extension programs are
attached to a slot using `BPF_PROG_TYPE_EXT` / `freplace`. Load order no longer
decides the result.

This lab does not require kernel tracing or `trace_pipe`. Verification reads the
chainer's pinned state map through `chainctl`.

Lab 4 does require kernel support for BPF extension programs
(`BPF_PROG_TYPE_EXT`) and `freplace`. If the chainer loads but attaching
`timeout_10` or `timeout_20` fails, the VM kernel may not support the production
style replacement mechanism used by this lab.

## Policy

The lab implements one mediation policy:

```text
FIRST_NONZERO_REPLY_WINS
```

After each slot returns, the chainer checks whether that slot wrote a nonzero
`skops->reply` for one of the reply-bearing sockops callbacks. The first writer
is remembered. Later writers are counted as double writers and then cleared, so
they cannot silently override the selected reply.

This mirrors the important production behavior while keeping the code readable.

## Build

```bash
make all
```

This builds:

```text
build/chainer.bpf.o
build/timeout_10.bpf.o
build/timeout_20.bpf.o
build/chainctl
```

## Full Verification

```bash
sudo make verify
```

The verifier:

1. Creates a temporary Lab 1 container.
2. Attaches `sockops_chainer` to `/sys/fs/cgroup/lab/<container>`.
3. Attaches `timeout_20` to slot `2` and `timeout_10` to slot `1`.
4. Triggers TCP socket activity inside the container.
5. Verifies the selected result is slot `1`, reply `10`.
6. Repeats with the opposite extension load order.
7. Verifies the selected result is still slot `1`, reply `10`.
8. Unloads BPF state and destroys the temporary container.

Expected important output:

```text
selected_priority=1
selected_reply=10
writer_count=2
double_writer_count=<nonzero>
Lab 4 verification passed
```

## Manual Run Against a Lab 1 Container

Create a reusable container:

```bash
cd ../01-container
sudo ./container-runtime.sh create c1
```

Load the chainer:

```bash
cd ../04-sockops-chainer
make all
sudo CONTAINER=c1 make load
```

Attach extensions by priority slot:

```bash
sudo CONTAINER=c1 SLOT=2 make attach_timeout_20
sudo CONTAINER=c1 SLOT=1 make attach_timeout_10
```

Trigger socket activity:

```bash
sudo ../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 45681))
server.listen(1)

client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
client.connect(("127.0.0.1", 45681))
conn, _ = server.accept()
client.send(b"x")
conn.recv(1)
conn.close()
client.close()
server.close()
PY
```

Inspect chainer state:

```bash
sudo CONTAINER=c1 make show
```

You should see:

```text
selected_priority=1
selected_reply=10
writer_count=2
```

Even though `timeout_20` was loaded first, slot `1` ran before slot `2`, so the
selected reply is deterministic.

## Cleanup

Unload Lab 4 BPF state while preserving the Lab 1 container:

```bash
sudo CONTAINER=c1 make unload
```

Destroy the Lab 1 container when you are done with all labs:

```bash
cd ../01-container
sudo ./container-runtime.sh destroy c1
```

## Troubleshooting

If `make verify` fails while loading `timeout_10.bpf.o` or
`timeout_20.bpf.o`, rebuild and rerun. `chainctl` prints the kernel verifier log
for extension load failures:

```bash
make clean
make all
sudo make verify
```

Useful feature checks:

```bash
bpftool feature probe kernel | grep -E 'ext|tracing|BPF_PROG_TYPE_EXT|BPF_LINK_TYPE_TRACING'
cat /proc/sys/net/core/bpf_jit_enable 2>/dev/null || true
```

Expected Lab 4 support:

```text
BPF_PROG_TYPE_EXT available
BPF_LINK_TYPE_TRACING / freplace support available
BPF JIT enabled when the kernel requires it for trampolines
```

If those are missing, Labs 1-3 can still run, but Lab 4's production-style
`freplace` chainer cannot be demonstrated on that VM kernel.

## Files

| File | Purpose |
|---|---|
| `src/chainer.bpf.c` | Explicit four-slot sockops chainer with first-writer mediation |
| `src/timeout_10.bpf.c` | Extension program that writes `skops->reply = 10` for `TIMEOUT_INIT` |
| `src/timeout_20.bpf.c` | Extension program that writes `skops->reply = 20` for `TIMEOUT_INIT` |
| `tools/chainctl.c` | Small libbpf loader for chainer load, freplace attach, and state reads |
| `scripts/verify.sh` | End-to-end priority and mediation verifier |
