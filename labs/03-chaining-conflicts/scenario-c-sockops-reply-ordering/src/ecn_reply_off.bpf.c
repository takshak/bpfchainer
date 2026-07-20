#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define BPF_SOCK_OPS_NEEDS_ECN 6

SEC("sockops")
int ecn_reply_off(struct bpf_sock_ops *skops)
{
	if (skops->op == BPF_SOCK_OPS_NEEDS_ECN) {
		skops->reply = 0;
		bpf_printk("scenario_c ecn_reply_off set reply=0\n");
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
