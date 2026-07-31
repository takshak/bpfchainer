#include <bpf/bpf.h>
#include <bpf/libbpf.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/bpf.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define LOG_BUF_SIZE (1024 * 1024)

struct monitored_chainer_state {
	uint32_t calls;
	uint32_t last_op;
	uint32_t selected_priority;
	uint32_t selected_reply;
	uint32_t writer_count;
	uint32_t conflict_count;
	uint32_t conflict_event_count;
	uint32_t conflict_seen_mask;
};

static char kernel_log_buf[LOG_BUF_SIZE];

static void clear_kernel_log(void)
{
	kernel_log_buf[0] = '\0';
}

static void print_kernel_log(const char *context)
{
	if (kernel_log_buf[0] != '\0')
		fprintf(stderr, "\n%s verifier log:\n%s\n", context, kernel_log_buf);
}

static struct bpf_object *open_bpf_object_with_log(const char *path)
{
	struct bpf_object_open_opts opts = {};

	clear_kernel_log();
	opts.sz = sizeof(opts);
	opts.kernel_log_buf = kernel_log_buf;
	opts.kernel_log_size = sizeof(kernel_log_buf);
	opts.kernel_log_level = 0;

	return bpf_object__open_file(path, &opts);
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"usage:\n"
		"  %s load-chainer <cgroup-path> <chainer-obj> <pin-dir>\n"
		"  %s attach-ext <pin-dir> <ext-obj> <prog-name> <slot>\n"
		"  %s show-state <pin-dir>\n"
		"  %s reset-state <pin-dir>\n",
		prog, prog, prog, prog);
}

static int join_path(char *out, size_t out_sz, const char *dir, const char *leaf)
{
	int written = snprintf(out, out_sz, "%s/%s", dir, leaf);

	if (written < 0 || (size_t)written >= out_sz) {
		fprintf(stderr, "path too long: %s/%s\n", dir, leaf);
		return -ENAMETOOLONG;
	}
	return 0;
}

static int ensure_dir(const char *path)
{
	if (mkdir(path, 0755) == 0 || errno == EEXIST)
		return 0;

	fprintf(stderr, "mkdir(%s): %s\n", path, strerror(errno));
	return -errno;
}

static int pin_link(struct bpf_link *link, const char *path)
{
	int err;

	unlink(path);
	err = bpf_link__pin(link, path);
	if (err)
		fprintf(stderr, "pin link %s: %s\n", path, strerror(-err));
	return err;
}

static int pin_program(struct bpf_program *prog, const char *path)
{
	int err;

	unlink(path);
	err = bpf_program__pin(prog, path);
	if (err)
		fprintf(stderr, "pin program %s: %s\n", path, strerror(-err));
	return err;
}

static int pin_map(struct bpf_map *map, const char *path)
{
	int err;

	unlink(path);
	err = bpf_map__pin(map, path);
	if (err)
		fprintf(stderr, "pin map %s: %s\n", path, strerror(-err));
	return err;
}

static int state_map_path(char *out, size_t out_sz, const char *pin_dir)
{
	return join_path(out, out_sz, pin_dir, "state_map");
}

static int events_map_path(char *out, size_t out_sz, const char *pin_dir)
{
	return join_path(out, out_sz, pin_dir, "events_map");
}

static int chainer_prog_path(char *out, size_t out_sz, const char *pin_dir)
{
	return join_path(out, out_sz, pin_dir, "chainer_prog");
}

static int reset_state_fd(int map_fd)
{
	uint32_t key = 0;
	struct monitored_chainer_state state = {};

	if (bpf_map_update_elem(map_fd, &key, &state, BPF_ANY) != 0) {
		fprintf(stderr, "reset state map: %s\n", strerror(errno));
		return -errno;
	}
	return 0;
}

static int do_load_chainer(const char *cgroup_path, const char *obj_path,
			   const char *pin_dir)
{
	char prog_pin[512], state_pin[512], events_pin[512];
	struct bpf_object *obj = NULL;
	struct bpf_program *prog;
	struct bpf_map *state_map;
	struct bpf_map *events_map;
	struct bpf_prog_attach_opts opts = {};
	int cgroup_fd = -1;
	int prog_fd;
	int state_fd;
	int err;

	if ((err = ensure_dir(pin_dir)) != 0)
		return err;
	if ((err = chainer_prog_path(prog_pin, sizeof(prog_pin), pin_dir)) != 0)
		return err;
	if ((err = state_map_path(state_pin, sizeof(state_pin), pin_dir)) != 0)
		return err;
	if ((err = events_map_path(events_pin, sizeof(events_pin), pin_dir)) != 0)
		return err;

	cgroup_fd = open(cgroup_path, O_RDONLY | O_DIRECTORY);
	if (cgroup_fd < 0) {
		fprintf(stderr, "open cgroup %s: %s\n", cgroup_path, strerror(errno));
		return -errno;
	}

	obj = open_bpf_object_with_log(obj_path);
	err = libbpf_get_error(obj);
	if (err) {
		fprintf(stderr, "open BPF object %s: %s\n", obj_path, strerror(-err));
		goto out;
	}

	err = bpf_object__load(obj);
	if (err) {
		fprintf(stderr, "load BPF object %s: %s\n", obj_path, strerror(-err));
		print_kernel_log("chainer load");
		goto out;
	}

	prog = bpf_object__find_program_by_name(obj, "monitored_sockops_chainer");
	state_map = bpf_object__find_map_by_name(obj, "chainer_state");
	events_map = bpf_object__find_map_by_name(obj, "conflict_events");
	if (!prog || !state_map || !events_map) {
		err = -ENOENT;
		fprintf(stderr, "missing monitored chainer program or maps\n");
		goto out;
	}

	prog_fd = bpf_program__fd(prog);
	state_fd = bpf_map__fd(state_map);
	if (prog_fd < 0 || state_fd < 0) {
		err = -EINVAL;
		fprintf(stderr, "invalid chainer program or state map fd\n");
		goto out;
	}

	opts.sz = sizeof(opts);
	opts.flags = BPF_F_ALLOW_MULTI;
	if (bpf_prog_attach_opts(prog_fd, cgroup_fd, BPF_CGROUP_SOCK_OPS, &opts) != 0) {
		err = -errno;
		fprintf(stderr, "attach chainer to %s: %s\n", cgroup_path, strerror(-err));
		goto out;
	}

	if ((err = pin_program(prog, prog_pin)) != 0)
		goto out;
	if ((err = pin_map(state_map, state_pin)) != 0)
		goto out;
	if ((err = pin_map(events_map, events_pin)) != 0)
		goto out;
	if ((err = reset_state_fd(state_fd)) != 0)
		goto out;

	printf("loaded monitored chainer\n");
	printf("cgroup=%s\n", cgroup_path);
	printf("pin_dir=%s\n", pin_dir);

out:
	if (obj)
		bpf_object__close(obj);
	if (cgroup_fd >= 0)
		close(cgroup_fd);
	return err;
}

static int parse_slot(const char *raw, uint32_t *slot)
{
	char *end = NULL;
	unsigned long value;

	errno = 0;
	value = strtoul(raw, &end, 10);
	if (errno || !end || *end != '\0' || value > 6) {
		fprintf(stderr, "slot must be 0..6: %s\n", raw);
		return -EINVAL;
	}

	*slot = (uint32_t)value;
	return 0;
}

static int do_attach_ext(const char *pin_dir, const char *obj_path,
			 const char *prog_name, const char *slot_raw)
{
	char chainer_pin[512], link_pin[512], prog_pin[512], target[64];
	struct bpf_object *obj = NULL;
	struct bpf_program *prog;
	struct bpf_link *link;
	uint32_t slot;
	int chainer_fd = -1;
	int err;

	if ((err = parse_slot(slot_raw, &slot)) != 0)
		return err;
	if ((err = chainer_prog_path(chainer_pin, sizeof(chainer_pin), pin_dir)) != 0)
		return err;

	snprintf(target, sizeof(target), "chain_slot_%u", slot);
	snprintf(link_pin, sizeof(link_pin), "%s/ext_link_slot_%u", pin_dir, slot);
	snprintf(prog_pin, sizeof(prog_pin), "%s/ext_prog_slot_%u", pin_dir, slot);

	chainer_fd = bpf_obj_get(chainer_pin);
	if (chainer_fd < 0) {
		fprintf(stderr, "open pinned chainer %s: %s\n", chainer_pin, strerror(errno));
		return -errno;
	}

	obj = open_bpf_object_with_log(obj_path);
	err = libbpf_get_error(obj);
	if (err) {
		fprintf(stderr, "open extension object %s: %s\n", obj_path, strerror(-err));
		goto out;
	}

	prog = bpf_object__find_program_by_name(obj, prog_name);
	if (!prog) {
		err = -ENOENT;
		fprintf(stderr, "missing program %s in %s\n", prog_name, obj_path);
		goto out;
	}

	err = bpf_program__set_attach_target(prog, chainer_fd, target);
	if (err) {
		fprintf(stderr, "set attach target %s: %s\n", target, strerror(-err));
		goto out;
	}

	err = bpf_object__load(obj);
	if (err) {
		fprintf(stderr, "load extension object %s: %s\n", obj_path, strerror(-err));
		print_kernel_log("extension load");
		goto out;
	}

	unlink(link_pin);
	unlink(prog_pin);

	link = bpf_program__attach_freplace(prog, chainer_fd, target);
	err = libbpf_get_error(link);
	if (err) {
		fprintf(stderr, "attach freplace %s -> %s: %s\n",
			prog_name, target, strerror(-err));
		goto out;
	}

	if ((err = pin_link(link, link_pin)) != 0)
		goto out;
	if ((err = pin_program(prog, prog_pin)) != 0)
		goto out;

	printf("attached extension\n");
	printf("program=%s\n", prog_name);
	printf("slot=%u\n", slot);
	printf("target=%s\n", target);

out:
	if (obj)
		bpf_object__close(obj);
	if (chainer_fd >= 0)
		close(chainer_fd);
	return err;
}

static int open_state_map(const char *pin_dir)
{
	char map_pin[512];
	int err;

	err = state_map_path(map_pin, sizeof(map_pin), pin_dir);
	if (err)
		return err;

	err = bpf_obj_get(map_pin);
	if (err < 0) {
		fprintf(stderr, "open state map %s: %s\n", map_pin, strerror(errno));
		return -errno;
	}
	return err;
}

static int do_show_state(const char *pin_dir)
{
	struct monitored_chainer_state state = {};
	uint32_t key = 0;
	int map_fd;
	int err = 0;

	map_fd = open_state_map(pin_dir);
	if (map_fd < 0)
		return map_fd;

	if (bpf_map_lookup_elem(map_fd, &key, &state) != 0) {
		err = -errno;
		fprintf(stderr, "read state map: %s\n", strerror(errno));
		goto out;
	}

	printf("calls=%u\n", state.calls);
	printf("last_op=%u\n", state.last_op);
	printf("selected_priority=%u\n", state.selected_priority);
	printf("selected_reply=%u\n", state.selected_reply);
	printf("writer_count=%u\n", state.writer_count);
	printf("conflict_count=%u\n", state.conflict_count);
	printf("conflict_event_count=%u\n", state.conflict_event_count);
	printf("conflict_seen_mask=%u\n", state.conflict_seen_mask);

out:
	close(map_fd);
	return err;
}

static int do_reset_state(const char *pin_dir)
{
	int map_fd;
	int err;

	map_fd = open_state_map(pin_dir);
	if (map_fd < 0)
		return map_fd;

	err = reset_state_fd(map_fd);
	close(map_fd);
	return err;
}

int main(int argc, char **argv)
{
	int err;

	libbpf_set_strict_mode(LIBBPF_STRICT_ALL);

	if (argc < 2) {
		usage(argv[0]);
		return 1;
	}

	if (strcmp(argv[1], "load-chainer") == 0) {
		if (argc != 5) {
			usage(argv[0]);
			return 1;
		}
		err = do_load_chainer(argv[2], argv[3], argv[4]);
	} else if (strcmp(argv[1], "attach-ext") == 0) {
		if (argc != 6) {
			usage(argv[0]);
			return 1;
		}
		err = do_attach_ext(argv[2], argv[3], argv[4], argv[5]);
	} else if (strcmp(argv[1], "show-state") == 0) {
		if (argc != 3) {
			usage(argv[0]);
			return 1;
		}
		err = do_show_state(argv[2]);
	} else if (strcmp(argv[1], "reset-state") == 0) {
		if (argc != 3) {
			usage(argv[0]);
			return 1;
		}
		err = do_reset_state(argv[2]);
	} else {
		usage(argv[0]);
		return 1;
	}

	return err ? 1 : 0;
}
