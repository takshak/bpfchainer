# Scenario B — Shared Map Side-Effect Conflict

This scenario shows that a cgroup-BPF verdict and BPF side effects are separate.

Two `cgroup/connect4` programs attach to the same Lab 01 container cgroup with
`BPF_ALLOW_MULTI`:

- `deny_writer` runs first, writes `final_decision = DENY`, and returns `0`.
- `allow_writer` runs second, writes `final_decision = ALLOW`, and returns `1`.

The final connection result is still denied because the earlier deny verdict is
sticky for `cgroup/connect4`. But the shared map says the final decision was
allow, because the later program still ran and overwrote the shared state.

```text
kernel verdict:    DENIED / EPERM
shared map state:  ALLOW
```

Takeaway: `BPF_ALLOW_MULTI` does not provide transactionality or side-effect
isolation. A later program may not override an earlier deny verdict, but it can
still mutate shared maps and leave misleading state behind.

This scenario does not require kernel tracing. Verification reads the pinned
shared map.

## Files

```text
src/deny_writer.bpf.c     writes shared_values[0].final_decision = DENY and returns 0
src/allow_writer.bpf.c    writes shared_values[0].final_decision = ALLOW and returns 1
scripts/load_order.sh     creates the shared pinned map and attaches deny then allow
scripts/show_state.sh     reads final_decision, last_writer, and writer counters
scripts/unload.sh         detaches, unpins programs, and removes the shared map
scripts/verify_order.sh   verifies the denied connection plus overwritten map state
```

## One-command Verification

```bash
make all
sudo make verify
```

Expected behavior:

```text
connect_errno=1
final_decision=1
last_writer=1
deny_count=1
allow_count=1
```

The important contradiction is:

```text
connect_errno=1      # kernel denied the connect
final_decision=1     # shared map says allow
```

## Manual Demo With `c1`

Create a Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh create c1
```

Load Scenario B:

```bash
cd ../03-chaining-conflicts/scenario-b-shared-map-clobbering
make all
sudo CONTAINER=c1 make load
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
    print(f"connect failed: errno={exc.errno} error={exc}")
finally:
    s.close()
PY
```

Expected command output:

```text
connect failed: errno=1 error=[Errno 1] Operation not permitted
```

Show the shared map:

```bash
sudo CONTAINER=c1 make show
```

Expected map output:

```text
final_decision=1
last_writer=1
deny_count=1
allow_count=1
```

## Cleanup

Unload only Scenario B BPF state:

```bash
sudo CONTAINER=c1 make unload
```

This removes:

```text
/sys/fs/bpf/bpfchainer_lab03b_c1_deny_writer
/sys/fs/bpf/bpfchainer_lab03b_c1_allow_writer
/sys/fs/bpf/bpfchainer_lab03b_c1_shared_values
```

It intentionally keeps `/sys/fs/cgroup/lab/c1` alive so you can run Scenario A
or C next.

When you are done with all scenarios, destroy the Lab 01 container:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```
