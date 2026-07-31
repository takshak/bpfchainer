# Exercise 05 — Monitoring a Chainer

Lab 04 built a production-style sockops chainer. Lab 05 adds observability:
the chainer detects conflicting `skops->reply` writers, emits ringbuf events,
and exposes chain state through a userspace tool.

This lab focuses on the monitoring pattern used by production systems:

```text
BPF chainer detects conflict
  -> emits structured event to ringbuf
  -> userspace monitor reads and reports the event
  -> state/introspection tools show what is attached
```

## What It Demonstrates

Two extension programs can both write `skops->reply`. The chainer mediates the
result with `FIRST_NONZERO_REPLY_WINS`, but it also reports later writers that
disagree with the selected winner.

The event shape is:

```text
op
winner_priority
winner_reply
conflict_priority
conflict_reply
timestamp_ns
```

## Verification Cases

`make verify` runs two cases.

Case 1:

```text
slot 1 -> timeout_10
slot 2 -> timeout_20
```

Expected:

```text
selected_priority=1
selected_reply=10
EVENT conflict_slot=2 conflict_reply=20
```

Case 2:

```text
slot 1 -> timeout_10
slot 2 -> timeout_20
slot 6 -> timeout_30
```

Expected:

```text
selected_priority=1
selected_reply=10
EVENT conflict_slot=2 conflict_reply=20
EVENT conflict_slot=6 conflict_reply=30
```

The chainer deduplicates conflict events by priority after each reset. Sockops
callbacks can fire multiple times for one TCP connection, but the tutorial
output stays readable: one event per conflicting slot.

## Run

```bash
make all
sudo make verify
```

The verifier creates a temporary Lab 01 container, loads the monitored chainer,
attaches extension programs, starts the ringbuf monitor, triggers TCP socket
activity, verifies the events/state, and cleans up.

## Three-Step Demo Flow

For teaching, use the split makefiles. They keep setup, traffic, and cleanup
as separate visible steps.

Step 1 creates or reuses the Lab 01 container, loads the monitored chainer,
attaches all three extension programs, resets the maps, and prints the chain:

```bash
sudo make -f Makefile.setup
```

This installs:

```text
slot 1 -> timeout_10
slot 2 -> timeout_20
slot 6 -> timeout_30
```

Step 2 sends one TCP connection inside the container. It also starts the
ringbuf monitor, waits for two conflict events, and prints map/chain state:

```bash
sudo make -f Makefile.traffic
```

Expected monitor output includes:

```text
EVENT ... winner_slot=1 winner_reply=10 conflict_slot=2 conflict_reply=20 ...
EVENT ... winner_slot=1 winner_reply=10 conflict_slot=6 conflict_reply=30 ...
```

Expected map state includes:

```text
selected_priority=1
selected_reply=10
conflict_event_count=2
```

Step 3 unloads Lab 05 BPF links/programs/pins and destroys the Lab 01
container:

```bash
sudo make -f Makefile.cleanup
```

To preserve the container and remove only Lab 05 BPF state:

```bash
sudo DESTROY_CONTAINER=0 make -f Makefile.cleanup
```

Useful introspection commands after setup or traffic:

```bash
sudo make show_chain
sudo make show
```

`make show_chain` uses pinned programs/links under
`/sys/fs/bpf/bpfchainer_lab05_c1` to show the chainer and extension slots.
`make show` uses `tools/chainctl show-state` to decode the chainer state map
and then runs `bpftool cgroup show` for the container cgroup.

## Manual Demo

Create a reusable Lab 01 container:

```bash
cd ../01-container
sudo ./container-runtime.sh create c1
```

Load the monitored chainer and attach three writers:

```bash
cd ../05-chainer-monitoring
make all
sudo CONTAINER=c1 make load
sudo CONTAINER=c1 SLOT=1 make attach_timeout_10
sudo CONTAINER=c1 SLOT=2 make attach_timeout_20
sudo CONTAINER=c1 SLOT=6 make attach_timeout_30
sudo CONTAINER=c1 make reset
```

Start the monitor in one terminal:

```bash
sudo CONTAINER=c1 EXPECTED_EVENTS=2 make monitor
```

Trigger socket activity in another terminal:

```bash
sudo ../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 45682))
server.listen(1)

client = socket.socket()
client.connect(("127.0.0.1", 45682))
conn, _ = server.accept()

client.send(b"x")
conn.recv(1)

conn.close()
client.close()
server.close()
PY
```

Inspect chain and state:

```bash
sudo CONTAINER=c1 make show_chain
sudo CONTAINER=c1 make show
```

Expected state includes:

```text
selected_priority=1
selected_reply=10
conflict_event_count=2
```

## Cleanup

Unload Lab 05 BPF state while preserving the Lab 01 container:

```bash
sudo CONTAINER=c1 make unload
```

Destroy the Lab 01 container when finished:

```bash
cd ../01-container
sudo ./container-runtime.sh destroy c1
```

## Files

| File | Purpose |
|---|---|
| `src/monitored_chainer.bpf.c` | Sockops chainer with ringbuf conflict events |
| `src/timeout_10.bpf.c` | Extension writer for slot 1 |
| `src/timeout_20.bpf.c` | Extension writer for slot 2 |
| `src/timeout_30.bpf.c` | Extension writer for slot 6 |
| `tools/chainctl.c` | Load, attach, reset, and show chainer state |
| `tools/monitor.c` | Ringbuf event reader |
| `scripts/show_chain.sh` | Simple chain introspection from pinned links/programs |

## TODO: Attachment Event Tracing

The original monitoring idea also included a BPF program that traces cgroup-BPF
attach/detach events. That is valuable, but it is intentionally left as future
work for this tutorial.

Possible approaches:

```text
kprobe/tracepoint around cgroup_bpf_attach or bpf_prog_attach
LSM hook if available
BPF iterator over programs/links
userspace polling with bpftool/libbpf
```

Why it is not implemented here:

```text
kernel symbol stability varies
tracefs/kprobe support varies across tutorial VMs
permissions differ across environments
it distracts from the core chainer monitoring pattern
```
