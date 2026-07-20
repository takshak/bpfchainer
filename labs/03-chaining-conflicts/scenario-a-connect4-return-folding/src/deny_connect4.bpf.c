#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define TARGET_PORT 1

SEC("cgroup/connect4")
int deny_connect4(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);

	if (port == TARGET_PORT) {
		bpf_printk("scenario_a deny port=%u return=DENY\n", port);
		return 0;
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
