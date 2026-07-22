#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define BCF_PASS 1
#define BPF_SOCK_OPS_TIMEOUT_INIT 1

SEC("freplace/chain_slot")
int timeout_10(struct bpf_sock_ops *skops)
{
	if (skops->op == BPF_SOCK_OPS_TIMEOUT_INIT) {
		skops->reply = 10;
		bpf_printk("lab04 timeout_10 wrote reply=10\n");
	}

	return BCF_PASS;
}

char LICENSE[] SEC("license") = "GPL";
