#ifndef SHARED_STATE_H
#define SHARED_STATE_H

struct sockops_state {
	__u32 needs_ecn_calls;
	__u32 off_count;
	__u32 on_count;
	__u32 observer_count;
	__u32 final_reply;
	__u32 last_writer;
};

#endif
