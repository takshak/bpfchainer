#ifndef SHARED_STATE_H
#define SHARED_STATE_H

struct shared_state {
	__u32 final_decision;
	__u32 last_writer;
	__u32 deny_count;
	__u32 allow_count;
};

#endif
