#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define TARGET_PORT 1
#define STATE_KEY 0

struct allow_state {
	__u32 allow_count;
	__u32 last_port;
};

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct allow_state);
} allow_state SEC(".maps");

SEC("cgroup/connect4")
int allow_connect4(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);
	__u32 key = STATE_KEY;
	struct allow_state *state;

	if (port == TARGET_PORT) {
		state = bpf_map_lookup_elem(&allow_state, &key);
		if (state) {
			state->allow_count++;
			state->last_port = port;
		}
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
