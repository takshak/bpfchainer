#ifndef BPF_HELPERS_MIN_H
#define BPF_HELPERS_MIN_H

#define SEC(name) __attribute__((section(name), used))
#define __always_inline inline __attribute__((always_inline))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name

#define BPF_MAP_TYPE_ARRAY 2
#define BPF_ANY 0

static long (*const bpf_map_update_elem)(void *map, const void *key,
					 const void *value, unsigned long long flags) = (void *)2;
static long (*const bpf_trace_printk)(const char *fmt, int fmt_size, ...) = (void *)6;

#define bpf_printk(fmt, ...)                         \
	({                                          \
		char ____fmt[] = fmt;               \
		bpf_trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__); \
	})

#endif
