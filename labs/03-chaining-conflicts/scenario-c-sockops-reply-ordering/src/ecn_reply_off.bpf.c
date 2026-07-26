#include "vmlinux.h"
#include "bpf_helpers_min.h"
#include "shared_state.h"

#define BPF_SOCK_OPS_NEEDS_ECN 6
#define STATE_KEY 0
#define WRITER_OFF 1

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct sockops_state);
} sockops_state SEC(".maps");

SEC("sockops")
int ecn_reply_off(struct bpf_sock_ops *skops)
{
	if (skops->op == BPF_SOCK_OPS_NEEDS_ECN) {
		__u32 key = STATE_KEY;
		struct sockops_state next = {};
		struct sockops_state *old;

		old = bpf_map_lookup_elem(&sockops_state, &key);
		if (old)
			next = *old;

		next.needs_ecn_calls++;
		next.off_count++;
		next.last_writer = WRITER_OFF;
		bpf_map_update_elem(&sockops_state, &key, &next, BPF_ANY);

		skops->reply = 0;
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
