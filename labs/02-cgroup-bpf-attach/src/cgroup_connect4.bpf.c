#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define TARGET_PORT 45680
#define STATE_KEY 0

struct connect4_state {
	__u32 connect_count;
	__u32 last_port;
};

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct connect4_state);
} connect4_state SEC(".maps");

SEC("cgroup/connect4")
int connect4_logger(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);
	__u32 key = STATE_KEY;
	struct connect4_state *state;

	if (port != TARGET_PORT)
		return 1;

	state = bpf_map_lookup_elem(&connect4_state, &key);
	if (state) {
		state->connect_count++;
		state->last_port = port;
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
