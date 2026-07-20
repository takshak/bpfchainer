# BPFChainer Labs

Hands-on exercises that build, from first principles, the machinery
BPFChainer stands on: containers made by hand, cgroup slices, eBPF
programs attached at the cgroup level, and finally a working program
chain with a live orchestrator.

> **Note:** the code in these labs is a pedagogical miniature written
> for teaching. It is not the BPFChainer implementation itself.

## Exercises

| # | Directory      | You will…                                              |
|---|----------------|--------------------------------------------------------|
| 1 | `01-container` | Build a tiny container runtime (create / enter / exec / destroy) using cgroups + namespaces |
| 2 | `02-cgroup-bpf-attach` | Compile, load, and attach a `cgroup/connect4` BPF program to a Lab 01 container cgroup |
| 3 | `03-chaining-conflicts` | Attach multiple BPF programs and observe return folding, shared-map clobbering, and `sock_ops` ordering |

*(More exercises coming: inheritance, the chainer, the orchestrator.)*

## Environment

The labs assume a Linux machine (or lab-provided microVM) where you are
root, with: `unshare`, `nsenter`, cgroup v2 mounted at `/sys/fs/cgroup`,
`clang`, `libbpf-dev`, and `bpftool`.
