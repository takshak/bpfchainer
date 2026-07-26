#ifndef BPF_HELPERS_MIN_H
#define BPF_HELPERS_MIN_H

#define SEC(name) __attribute__((section(name), used))
#define __always_inline inline __attribute__((always_inline))
#define __uint(name, val) int (*name)[val]
#define __type(name, val) typeof(val) *name

#define BPF_MAP_TYPE_ARRAY 2

static void *(*const bpf_map_lookup_elem)(void *map, const void *key) = (void *)1;

#endif
