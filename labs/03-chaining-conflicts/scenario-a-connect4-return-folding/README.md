# Scenario A — `connect4` Return Folding

This scenario shows that multiple `cgroup/connect4` programs do not compose as
"last return value wins".

Two programs attach to the same Lab 01 container cgroup with `BPF_ALLOW_MULTI`:

- `deny_connect4` returns `0` for destination port `1`.
- `allow_connect4` always returns `1`.

Both programs execute, but the final connect result is still denied.

```text
deny returns 0
allow returns 1
final result: -EPERM
```

Takeaway: for `cgroup/connect4`, deny is sticky. A later allow does not clear an
earlier deny.

## Files

```text
src/deny_connect4.bpf.c    returns DENY for port 1
src/allow_connect4.bpf.c   always returns ALLOW
scripts/load_multi.sh      loads both programs and attaches deny first
scripts/unload.sh          detaches and unpins only Scenario A programs
scripts/verify.sh          creates a temporary Lab 01 container and tests EPERM
kernel_flow.md             explains the relevant kernel return folding
```

## One-command Verification

```bash
make all
sudo make verify
```

Expected result:

```text
scenario_a deny port=1 return=DENY
scenario_a allow port=1 return=ALLOW
connect_errno=1
```

The important part is that both trace lines appear, but userspace still gets
`EPERM`.

## Manual Demo With `c1`

Create a Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh create c1
```

Load Scenario A:

```bash
cd ../03-chaining-conflicts/scenario-a-connect4-return-folding
make all
sudo CONTAINER=c1 make load
```

Inspect the attachment order:

```bash
sudo bpftool cgroup show /sys/fs/cgroup/lab/c1
```

In a second terminal, watch trace output:

```bash
sudo cat /sys/kernel/tracing/trace_pipe
```

Trigger the effect:

```bash
sudo ../../01-container/container-runtime.sh exec c1 python3 - <<'PY'
import socket

s = socket.socket()
s.settimeout(1)
try:
    s.connect(("127.0.0.1", 1))
    print("connect succeeded")
except OSError as exc:
    print(f"connect failed: errno={exc.errno} error={exc}")
finally:
    s.close()
PY
```

Expected command output:

```text
connect failed: errno=1 error=[Errno 1] Operation not permitted
```

Expected trace output:

```text
scenario_a deny port=1 return=DENY
scenario_a allow port=1 return=ALLOW
```

## Cleanup

Unload only Scenario A BPF state:

```bash
sudo CONTAINER=c1 make unload
```

This removes:

```text
/sys/fs/bpf/bpfchainer_lab03a_c1_deny
/sys/fs/bpf/bpfchainer_lab03a_c1_allow
```

It intentionally keeps `/sys/fs/cgroup/lab/c1` alive so you can run Scenario B
or C next.

When you are done with all scenarios, destroy the Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```
