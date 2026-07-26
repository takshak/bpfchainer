#include "vmlinux.h"
#include "bpf_helpers_min.h"
#include "shared_state.h"

#define SHARED_KEY 0
#define TARGET_PORT 45679
#define DECISION_DENY 0

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct shared_state);
} shared_values SEC(".maps");

SEC("cgroup/connect4")
int deny_writer_connect4(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);
	__u32 key = SHARED_KEY;
	struct shared_state next = {};
	struct shared_state *old;

	if (port != TARGET_PORT)
		return 1;

	old = bpf_map_lookup_elem(&shared_values, &key);
	if (old)
		next = *old;

	next.final_decision = DECISION_DENY;
	next.last_writer = DECISION_DENY;
	next.deny_count++;
	bpf_map_update_elem(&shared_values, &key, &next, BPF_ANY);

	return 0;
}

char LICENSE[] SEC("license") = "GPL";
