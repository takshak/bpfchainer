#ifndef CHAINER_EVENTS_H
#define CHAINER_EVENTS_H

#define PRIORITY_NONE 0xffffffff

struct monitored_chainer_state {
	__u32 calls;
	__u32 last_op;
	__u32 selected_priority;
	__u32 selected_reply;
	__u32 writer_count;
	__u32 conflict_count;
	__u32 conflict_event_count;
	__u32 conflict_seen_mask;
};

struct conflict_event {
	__u32 op;
	__u32 winner_priority;
	__u32 winner_reply;
	__u32 conflict_priority;
	__u32 conflict_reply;
	__u64 timestamp_ns;
};

#endif
