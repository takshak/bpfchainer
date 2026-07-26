# Exercise 02 — Attach eBPF to a Container Cgroup

Lab 01 built a tiny container runtime. This lab uses the cgroup created by that
runtime as the attachment point for a `cgroup/connect4` eBPF program.

The key idea:

```text
container c1
  namespaces: what the process sees
  cgroup:    /sys/fs/cgroup/lab/c1
             where cgroup-BPF programs attach
```

This lab does not create or destroy container cgroups during normal `load` and
`unload`. Lab 01 owns container lifecycle. Lab 02 owns BPF program lifecycle.

The example program allows every connection and updates a small BPF map only
for IPv4 connects to destination port `45680`. Filtering to one lab port keeps
the output deterministic while still demonstrating the attach point. This lab
does not require kernel tracing or `trace_pipe`.

## Build

```bash
make all
```

This generates `build/vmlinux.h` from `/sys/kernel/btf/vmlinux` and compiles:

```text
build/cgroup_connect4.bpf.o
```

## One-command Verification

```bash
sudo make verify
```

The verifier:

1. Creates a temporary Lab 01 container.
2. Loads and pins the `cgroup/connect4` BPF program.
3. Attaches it to `/sys/fs/cgroup/lab/<temporary-container>`.
4. Runs a Python `connect()` from inside the container with Lab 01 `exec`.
5. Confirms the BPF program updated its pinned state map.
6. Detaches, unpins, and destroys the temporary container.

## Manual Flow

Create a container with Lab 01:

```bash
cd ../01-container
sudo ./container-runtime.sh create c1
```

Attach the BPF program to that container cgroup:

```bash
cd ../02-cgroup-bpf-attach
make all
sudo CONTAINER=c1 make load
```

Trigger the hook from inside the container:

```bash
sudo ../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(1)
try:
    sock.connect(("127.0.0.1", 45680))
except OSError as exc:
    print(exc)
finally:
    sock.close()
PY
```

Observe BPF output through the pinned map:

```bash
sudo CONTAINER=c1 make show
```

Expected output includes:

```text
connect_count=1
last_port=45680
```

Cleanup BPF state:

```bash
sudo CONTAINER=c1 make unload
```

Destroy the container:

```bash
cd ../01-container
sudo ./container-runtime.sh destroy c1
```

## Why Lab 01 `exec` Matters

`nsenter` joins namespaces, not cgroups. Lab 01 `exec` first writes the command
process into `/sys/fs/cgroup/lab/<name>/cgroup.procs`, then enters the
container namespaces. Without that cgroup move, traffic from the command would
not hit BPF programs attached to the container cgroup.

## Useful Commands

Inspect the attachment:

```bash
sudo bpftool cgroup show /sys/fs/cgroup/lab/c1
```

Inspect the pinned program:

```bash
sudo bpftool prog show pinned /sys/fs/bpf/bpfchainer_lab02_c1_connect4
```

Detach and unpin:

```bash
sudo CONTAINER=c1 make unload
```

## Requirements

- Linux with cgroup v2 mounted at `/sys/fs/cgroup`
- BTF at `/sys/kernel/btf/vmlinux`
- `clang` with BPF target support
- `bpftool`
- `python3`
- root privileges for BPF loading and cgroup attach
