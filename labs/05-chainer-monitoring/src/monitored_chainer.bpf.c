#include "vmlinux.h"
#include "bpf_helpers_min.h"
#include "chainer_events.h"

#define BCF_PASS 1
#define BCF_ABORTED 0

#define STATE_KEY 0

#define BPF_SOCK_OPS_TIMEOUT_INIT 1
#define BPF_SOCK_OPS_RWND_INIT 2
#define BPF_SOCK_OPS_NEEDS_ECN 6
#define BPF_SOCK_OPS_BASE_RTT 12

struct {
	__uint(type, BPF_MAP_TYPE_ARRAY);
	__uint(max_entries, 1);
	__type(key, __u32);
	__type(value, struct monitored_chainer_state);
} chainer_state SEC(".maps");

struct {
	__uint(type, BPF_MAP_TYPE_RINGBUF);
	__uint(max_entries, 256 * 1024);
} conflict_events SEC(".maps");

struct invocation_state {
	__u32 selected_reply;
	__u32 selected_priority;
	__u32 writer_count;
	__u32 conflict_count;
};

__noinline int chain_slot_0(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_1(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_2(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_3(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_4(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_5(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }
__noinline int chain_slot_6(struct bpf_sock_ops *skops) { return skops ? BCF_PASS : BCF_ABORTED; }

static __always_inline int valid_reply_op(__u32 op)
{
	switch (op) {
	case BPF_SOCK_OPS_TIMEOUT_INIT:
	case BPF_SOCK_OPS_RWND_INIT:
	case BPF_SOCK_OPS_NEEDS_ECN:
	case BPF_SOCK_OPS_BASE_RTT:
		return 1;
	default:
		return 0;
	}
}

static __always_inline void pre_chain(struct bpf_sock_ops *skops,
				      struct invocation_state *inv)
{
	inv->selected_reply = 0;
	inv->selected_priority = PRIORITY_NONE;
	inv->writer_count = 0;
	inv->conflict_count = 0;
	skops->reply = 0;
}

static __noinline void clear_reply(struct bpf_sock_ops *skops)
{
	skops->reply = 0;
}

static __always_inline void emit_conflict_once(struct bpf_sock_ops *skops,
					       struct invocation_state *inv,
					       __u32 priority,
					       __u32 reply)
{
	__u32 key = STATE_KEY;
	__u32 bit = 1U << priority;
	struct monitored_chainer_state next = {};
	struct monitored_chainer_state *old;
	struct conflict_event event = {};

	old = bpf_map_lookup_elem(&chainer_state, &key);
	if (old)
		next = *old;

	if (next.conflict_seen_mask & bit)
		return;

	next.conflict_seen_mask |= bit;
	next.conflict_event_count++;
	bpf_map_update_elem(&chainer_state, &key, &next, BPF_ANY);

	event.op = skops->op;
	event.winner_priority = inv->selected_priority;
	event.winner_reply = inv->selected_reply;
	event.conflict_priority = priority;
	event.conflict_reply = reply;
	event.timestamp_ns = bpf_ktime_get_ns();
	bpf_ringbuf_output(&conflict_events, &event, sizeof(event), 0);
}

static __always_inline void observe_slot_reply(struct bpf_sock_ops *skops,
					       struct invocation_state *inv,
					       __u32 priority)
{
	__u32 reply = skops->reply;

	if (reply != 0 && valid_reply_op(skops->op)) {
		inv->writer_count++;
		if (inv->selected_reply == 0) {
			inv->selected_reply = reply;
			inv->selected_priority = priority;
		} else if (reply != inv->selected_reply) {
			inv->conflict_count++;
			emit_conflict_once(skops, inv, priority, reply);
		}
	}

}

static __always_inline void update_debug_state(struct bpf_sock_ops *skops,
					       struct invocation_state *inv)
{
	__u32 key = STATE_KEY;
	struct monitored_chainer_state next = {};
	struct monitored_chainer_state *old;

	old = bpf_map_lookup_elem(&chainer_state, &key);
	if (old)
		next = *old;

	next.calls++;
	next.last_op = skops->op;

	if (inv->writer_count > 0) {
		next.selected_priority = inv->selected_priority;
		next.selected_reply = inv->selected_reply;
		next.writer_count = inv->writer_count;
		next.conflict_count += inv->conflict_count;
	}

	bpf_map_update_elem(&chainer_state, &key, &next, BPF_ANY);
}

static __always_inline void post_chain(struct bpf_sock_ops *skops,
				       struct invocation_state *inv)
{
	if (inv->selected_reply != 0)
		skops->reply = inv->selected_reply;
}

SEC("sockops")
int monitored_sockops_chainer(struct bpf_sock_ops *skops)
{
	struct invocation_state inv = {};
	int ret;

	pre_chain(skops, &inv);

	ret = chain_slot_0(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 0);
	clear_reply(skops);

	ret = chain_slot_1(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 1);
	clear_reply(skops);

	ret = chain_slot_2(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 2);
	clear_reply(skops);

	ret = chain_slot_3(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 3);
	clear_reply(skops);

	ret = chain_slot_4(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 4);
	clear_reply(skops);

	ret = chain_slot_5(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 5);
	clear_reply(skops);

	ret = chain_slot_6(skops);
	if (ret != BCF_PASS) return 0;
	observe_slot_reply(skops, &inv, 6);
	clear_reply(skops);

	post_chain(skops, &inv);
	update_debug_state(skops, &inv);

	return 1;
}

char LICENSE[] SEC("license") = "GPL";
