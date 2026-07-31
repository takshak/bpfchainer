#ifndef BPF_HELPERS_MIN_H
#define BPF_HELPERS_MIN_H

#define SEC(name) __attribute__((section(name), used))
#define __always_inline inline __attribute__((always_inline))
#define __noinline __attribute__((noinline))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name

#define BPF_MAP_TYPE_ARRAY 2
#define BPF_MAP_TYPE_RINGBUF 27
#define BPF_ANY 0

static void *(*const bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;
static long (*const bpf_map_update_elem)(void *map, const void *key,
					 const void *value,
					 unsigned long long flags) = (void *)2;
static unsigned long long (*const bpf_ktime_get_ns)(void) = (void *)5;
static long (*const bpf_ringbuf_output)(void *ringbuf, void *data,
					unsigned long long size,
					unsigned long long flags) = (void *)130;

#endif
