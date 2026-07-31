#include <bpf/bpf.h>
#include <bpf/libbpf.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

struct conflict_event {
	uint32_t op;
	uint32_t winner_priority;
	uint32_t winner_reply;
	uint32_t conflict_priority;
	uint32_t conflict_reply;
	uint64_t timestamp_ns;
};

struct monitor_state {
	int seen;
	int expected;
};

static void usage(const char *prog)
{
	fprintf(stderr, "usage: %s <pin-dir> [expected-events] [timeout-ms]\n", prog);
}

static int handle_event(void *ctx, void *data, size_t data_sz)
{
	struct monitor_state *state = ctx;
	const struct conflict_event *event = data;

	if (data_sz < sizeof(*event)) {
		fprintf(stderr, "short conflict event: %zu bytes\n", data_sz);
		return 0;
	}

	state->seen++;
	printf("EVENT op=%u winner_slot=%u winner_reply=%u conflict_slot=%u conflict_reply=%u timestamp_ns=%llu\n",
	       event->op,
	       event->winner_priority,
	       event->winner_reply,
	       event->conflict_priority,
	       event->conflict_reply,
	       (unsigned long long)event->timestamp_ns);
	fflush(stdout);

	return 0;
}

static long monotonic_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv)
{
	char map_path[512];
	struct ring_buffer *rb;
	struct monitor_state state = {};
	int timeout_ms = 5000;
	int map_fd;
	long deadline;
	int err = 0;

	if (argc < 2 || argc > 4) {
		usage(argv[0]);
		return 1;
	}

	if (argc >= 3)
		state.expected = atoi(argv[2]);
	if (argc >= 4)
		timeout_ms = atoi(argv[3]);

	if (snprintf(map_path, sizeof(map_path), "%s/events_map", argv[1]) >= (int)sizeof(map_path)) {
		fprintf(stderr, "events map path too long\n");
		return 1;
	}

	map_fd = bpf_obj_get(map_path);
	if (map_fd < 0) {
		fprintf(stderr, "open events map %s: %s\n", map_path, strerror(errno));
		return 1;
	}

	rb = ring_buffer__new(map_fd, handle_event, &state, NULL);
	if (!rb) {
		fprintf(stderr, "create ring buffer: %s\n", strerror(errno));
		close(map_fd);
		return 1;
	}

	deadline = monotonic_ms() + timeout_ms;
	while (state.expected == 0 || state.seen < state.expected) {
		long remaining = deadline - monotonic_ms();

		if (remaining <= 0)
			break;

		err = ring_buffer__poll(rb, remaining > 250 ? 250 : (int)remaining);
		if (err < 0 && err != -EINTR) {
			fprintf(stderr, "ring buffer poll: %s\n", strerror(-err));
			break;
		}
	}

	printf("events_seen=%d\n", state.seen);

	ring_buffer__free(rb);
	close(map_fd);

	if (state.expected > 0 && state.seen < state.expected)
		return 2;

	return err < 0 ? 1 : 0;
}
