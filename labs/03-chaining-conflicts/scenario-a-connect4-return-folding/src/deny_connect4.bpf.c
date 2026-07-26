#include "vmlinux.h"
#include "bpf_helpers_min.h"

#define TARGET_PORT 1
#define STATE_KEY 0

struct deny_state {
	__u32 deny_count;
	__u32 last_port;
};

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct deny_state);
} deny_state SEC(".maps");

SEC("cgroup/connect4")
int deny_connect4(struct bpf_sock_addr *ctx)
{
	__u16 port = __builtin_bswap16((__u16)ctx->user_port);
	__u32 key = STATE_KEY;
	struct deny_state *state;

	if (port == TARGET_PORT) {
		state = bpf_map_lookup_elem(&deny_state, &key);
		if (state) {
			state->deny_count++;
			state->last_port = port;
		}
		return 0;
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
