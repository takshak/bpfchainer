# Exercise 01 — Build a Container by Hand

A container is not a box. It is a **process wearing isolation**: a few
namespaces (what it can *see*) plus a cgroup slice (where the kernel
*accounts and controls* it — and where eBPF programs attach).

`container-runtime.sh` is a tiny container runtime — under 150 lines of
bash — with three verbs:

```
./container-runtime.sh create  c1     # cgroup slice + namespaces + init
./container-runtime.sh enter   c1     # a shell inside (like docker exec)
./container-runtime.sh destroy c1     # kill + clean up
```

## Run it

```bash
./container-runtime.sh create c1
cat /run/containers/c1.pid            # the container's init, host view
systemd-cgls | grep -A3 lab           # the cgroup slice, with the init in it

./container-runtime.sh enter c1
# prompt: root@c1
ps aux                                # PID 1 is sleep — a two-line world
hostname                              # c1
cat /proc/self/cgroup                 # .../lab/c1
exit

./container-runtime.sh destroy c1
```

## What to notice

- **The same process has two PIDs.** `cat /run/containers/c1.pid` on the
  host vs `ps aux` inside (where init is PID 1). Same process, two views —
  that is a pid namespace.
- **The cgroup is just a directory.** `ls /sys/fs/cgroup/lab/c1/` —
  membership is PIDs listed in `cgroup.procs`. This directory is where
  eBPF programs will attach in the next exercise.

## Questions

1. In `start_container`, the pidfile records the **child** of the
   `unshare` process, with a retry loop, and refuses to fall back to the
   parent. Change it to record `$!` (the parent) and re-run
   `enter` + `ps aux`. What breaks, and why does the unshare parent not
   live in the new pid namespace?
2. Send `kill <init-pid>` (plain SIGTERM) from the host to a running
   container's init. It survives. Why do pid-namespace init processes
   ignore signals they have no handler for? What kills them?
3. In `enter_container`, comment out the `echo $$ > .../cgroup.procs`
   line. The shell still "enters" the container fine. What, invisibly,
   would now be wrong — and why would every BPF counter in the later
   exercises read zero for traffic you send from that shell?
4. `destroy` writes `1` to `cgroup.kill` instead of killing the pidfile
   PID. What does that buy when the pidfile is stale or wrong?
