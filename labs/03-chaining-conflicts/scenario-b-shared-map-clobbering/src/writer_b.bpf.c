#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define SHARED_KEY 0
#define TARGET_PORT 45679
#define WRITER_B_VALUE 0xb

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, __u32);
} shared_values SEC(".maps");

SEC("cgroup/connect4")
int writer_b_connect4(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);
	__u32 key = SHARED_KEY;
	__u32 value = WRITER_B_VALUE;

	if (port != TARGET_PORT)
		return 1;

	bpf_map_update_elem(&shared_values, &key, &value, BPF_ANY);
	bpf_printk("scenario_b writer_b port=%u value=%u\n", port, value);

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
