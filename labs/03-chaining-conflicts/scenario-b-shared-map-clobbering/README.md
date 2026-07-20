# Scenario B — Shared Map Key Clobbering

This scenario shows that shared BPF maps do not provide ownership boundaries.

Two `cgroup/connect4` programs attach to the same Lab 01 container cgroup with
`BPF_ALLOW_MULTI`. Both write to the same pinned array map when an IPv4 connect
targets port `45679`:

- key `0`
- `writer_a` writes value `10`
- `writer_b` writes value `11`

Both programs return `1`, so they allow the connection attempt. The connection
result is not the point of this lab. The point is that final shared map state
depends on attach order.

## Files

```text
src/writer_a.bpf.c       writes shared_values[0] = 10
src/writer_b.bpf.c       writes shared_values[0] = 11
scripts/load_order.sh    creates the shared pinned map and attaches in order
scripts/unload.sh        detaches, unpins programs, and removes the shared map
scripts/verify_order.sh  verifies both attach orders
```

## One-command Verification

```bash
make all
sudo make verify
```

Expected behavior:

- `b-a`: `writer_b` runs first, `writer_a` runs last, final map value is `10`.
- `a-b`: `writer_a` runs first, `writer_b` runs last, final map value is `11`.

This is deterministic clobbering for one hook invocation, not random memory
corruption. The bug pattern is shared state without ownership boundaries.

## Manual Demo With `c1`

Create a Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh create c1
```

Load with `writer_b` attached last:

```bash
cd ../03-chaining-conflicts/scenario-b-shared-map-clobbering
make all
sudo CONTAINER=c1 make load_b_last
```

Trigger one connect to port `45679`:

```bash
sudo ../../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", 45679))
except OSError as exc:
    print(exc)
finally:
    s.close()
PY
```

Dump the shared map:

```bash
sudo bpftool map dump pinned /sys/fs/bpf/bpfchainer_lab03b_c1_shared_values
```

Expected final value when `writer_b` runs last:

```text
0b 00 00 00
```

Reverse the order so `writer_a` runs last:

```bash
sudo CONTAINER=c1 make unload
sudo CONTAINER=c1 make load_a_last
```

Trigger again and dump the map:

```bash
sudo ../../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", 45679))
except OSError as exc:
    print(f"connect expectedly failed: {exc}")
finally:
    s.close()
PY
sudo bpftool map dump pinned /sys/fs/bpf/bpfchainer_lab03b_c1_shared_values
```

Expected final value when `writer_a` runs last:

```text
0a 00 00 00
```

## Cleanup

Unload only Scenario B BPF state:

```bash
sudo CONTAINER=c1 make unload
```

This removes:

```text
/sys/fs/bpf/bpfchainer_lab03b_c1_writer_a
/sys/fs/bpf/bpfchainer_lab03b_c1_writer_b
/sys/fs/bpf/bpfchainer_lab03b_c1_shared_values
```

It intentionally keeps `/sys/fs/cgroup/lab/c1` alive so you can run Scenario A
or C next.

When you are done with all scenarios, destroy the Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```
