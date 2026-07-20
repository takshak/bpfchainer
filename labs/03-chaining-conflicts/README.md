# Exercise 03 — Chaining Conflicts

Lab 01 created container cgroups. Lab 02 attached one BPF program to one
container cgroup. Lab 03 attaches multiple BPF programs and shows why chaining
needs explicit conflict policy.

The shared theme:

```text
BPF chaining is not automatically safe.
Different cgroup-BPF hooks compose differently.
Attach order, return folding, shared maps, and mutable context fields matter.
```

## Scenarios

| Scenario | Directory | Lesson |
|---|---|---|
| A | `scenario-a-connect4-return-folding` | `cgroup/connect4` deny is sticky: a later allow does not clear an earlier deny. |
| B | `scenario-b-shared-map-clobbering` | Shared maps have no ownership boundary: two programs can overwrite the same key. |
| C | `scenario-c-sockops-reply-ordering` | `cgroup/sock_ops` programs share mutable context: the last writer to `skops->reply` wins. |

## Run Everything

```bash
sudo make verify
```

Each scenario verifier creates its own temporary Lab 01 container, attaches BPF
to `/sys/fs/cgroup/lab/<temporary-container>`, runs the experiment, unloads BPF
state, and destroys the temporary container.

## Manual Pattern

Create a reusable Lab 01 container:

```bash
cd ../01-container
sudo ./container-runtime.sh create c1
```

Run one scenario against that container:

```bash
cd ../03-chaining-conflicts/scenario-a-connect4-return-folding
make all
sudo CONTAINER=c1 make load
sudo CONTAINER=c1 make unload
```

Destroy the container when finished:

```bash
cd ../../01-container
sudo ./container-runtime.sh destroy c1
```

Scenario `unload` targets only BPF state. It intentionally preserves the
container cgroup because Lab 01 owns container lifecycle.
