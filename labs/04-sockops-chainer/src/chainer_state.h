#ifndef CHAINER_STATE_H
#define CHAINER_STATE_H

struct lab04_chainer_state {
	__u32 calls;
	__u32 last_op;
	__u32 last_writer_op;
	__u32 selected_priority;
	__u32 selected_reply;
	__u32 writer_count;
	__u32 double_writer_count;
};

#endif
