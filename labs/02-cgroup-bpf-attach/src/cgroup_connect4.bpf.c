#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define TARGET_PORT 45680

SEC("cgroup/connect4")
int connect4_logger(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);

	if (port != TARGET_PORT)
		return 1;

	bpf_printk("lab02 cgroup/connect4 dst_port=%u\n", port);

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
