# Kernel Flow For `cgroup/connect4` Return Values

For TCP IPv4 `connect()`, the high-level path is:

```text
userspace connect()
  -> inet_stream_connect()
  -> sk->sk_prot->pre_connect()
  -> tcp_v4_pre_connect()
  -> BPF_CGROUP_RUN_PROG_INET4_CONNECT()
  -> __cgroup_bpf_run_filter_sock_addr()
  -> bpf_prog_run_array_cg()
```

The important logic is in `bpf_prog_run_array_cg()`:

```c
while ((prog = READ_ONCE(item->prog))) {
	func_ret = run_prog(prog, ctx);
	if (!func_ret && !IS_ERR_VALUE((long)run_ctx.retval))
		run_ctx.retval = -EPERM;
	item++;
}
return run_ctx.retval;
```

This means:

- The kernel does not stop when one program returns `0`.
- Later programs in the effective cgroup program array still execute.
- The first program returning `0` sets the accumulated return value to
  `-EPERM`.
- A later program returning `1` does not reset the accumulated return value back
  to success.

For `cgroup/connect4`, return `1` means allow and return `0` means deny. With
multiple attached programs, deny is sticky.
