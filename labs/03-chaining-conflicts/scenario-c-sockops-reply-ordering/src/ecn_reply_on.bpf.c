#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define BPF_SOCK_OPS_NEEDS_ECN 6

SEC("sockops")
int ecn_reply_on(struct bpf_sock_ops *skops)
{
	if (skops->op == BPF_SOCK_OPS_NEEDS_ECN) {
		skops->reply = 1;
		bpf_printk("scenario_c ecn_reply_on set reply=1\n");
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
