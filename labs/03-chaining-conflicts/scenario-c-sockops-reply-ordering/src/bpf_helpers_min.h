#ifndef BPF_HELPERS_MIN_H
#define BPF_HELPERS_MIN_H

#define SEC(name) __attribute__((section(name), used))
#define __always_inline inline __attribute__((always_inline))

static long (*const bpf_trace_printk)(const char *fmt, int fmt_size, ...) = (void *)6;

#define bpf_printk(fmt, ...)                         \
	({                                          \
		char ____fmt[] = fmt;               \
		bpf_trace_printk(____fmt, sizeof(____fmt), ##__VA_ARGS__); \
	})

#endif
