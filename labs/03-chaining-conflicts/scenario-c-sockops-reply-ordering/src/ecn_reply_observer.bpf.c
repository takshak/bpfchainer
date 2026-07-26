#include "vmlinux.h"
#include "bpf_helpers_min.h"
#include "shared_state.h"

#define BPF_SOCK_OPS_NEEDS_ECN 6
#define STATE_KEY 0

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct sockops_state);
} sockops_state SEC(".maps");

SEC("sockops")
int ecn_reply_observer(struct bpf_sock_ops *skops)
{
	if (skops->op == BPF_SOCK_OPS_NEEDS_ECN) {
		__u32 key = STATE_KEY;
		struct sockops_state next = {};
		struct sockops_state *old;

		old = bpf_map_lookup_elem(&sockops_state, &key);
		if (old)
			next = *old;

		next.observer_count++;
		next.final_reply = skops->reply;
		bpf_map_update_elem(&sockops_state, &key, &next, BPF_ANY);
	}

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
