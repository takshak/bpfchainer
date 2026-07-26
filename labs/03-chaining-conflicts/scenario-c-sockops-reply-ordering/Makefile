ARCH ?= $(shell uname -m)
BPF_ARCH := $(if $(filter x86_64,$(ARCH)),x86,$(if $(filter aarch64 arm64,$(ARCH)),arm64,$(ARCH)))
CLANG ?= $(shell command -v clang 2>/dev/null || echo clang)
BPFTOOL ?= bpftool
OUTPUT ?= build

BPF_SRCS := $(wildcard src/*.bpf.c)
BPF_OBJS := $(patsubst src/%.bpf.c,$(OUTPUT)/%.bpf.o,$(BPF_SRCS))
BPF_CFLAGS := -O2 -g -target bpf -D__TARGET_ARCH_$(BPF_ARCH)

.PHONY: all clean doctor load_on_last load_off_last unload show verify verify_on_last verify_off_last demo_tcpdump_on_last demo_tcpdump_off_last demo_tcpdump

all: doctor $(BPF_OBJS)

doctor:
	@command -v $(BPFTOOL) >/dev/null 2>&1 || { echo "missing bpftool"; exit 1; }
	@command -v $(CLANG) >/dev/null 2>&1 || { echo "missing clang with BPF target support"; exit 1; }
	@test -r /sys/kernel/btf/vmlinux || { echo "missing readable /sys/kernel/btf/vmlinux"; exit 1; }
	@mount | grep -q 'type cgroup2 ' || { echo "cgroup v2 is required"; exit 1; }
	@printf 'CLANG=%s\n' "$(CLANG)"
	@printf 'BPFTOOL=%s\n' "$(BPFTOOL)"
	@printf 'ARCH=%s BPF_ARCH=%s\n' "$(ARCH)" "$(BPF_ARCH)"

$(OUTPUT):
	mkdir -p $(OUTPUT)

$(OUTPUT)/vmlinux.h: | $(OUTPUT)
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

$(OUTPUT)/%.bpf.o: src/%.bpf.c src/bpf_helpers_min.h src/shared_state.h $(OUTPUT)/vmlinux.h | $(OUTPUT)
	$(CLANG) $(BPF_CFLAGS) -I$(OUTPUT) -Isrc -c $< -o $@

verify_on_last: $(BPF_OBJS)
	./scripts/verify_order.sh off-on

verify_off_last: $(BPF_OBJS)
	./scripts/verify_order.sh on-off

verify: verify_on_last verify_off_last

demo_tcpdump_on_last: $(BPF_OBJS)
	./scripts/demo_tcpdump.sh off-on

demo_tcpdump_off_last: $(BPF_OBJS)
	./scripts/demo_tcpdump.sh on-off

demo_tcpdump: demo_tcpdump_on_last demo_tcpdump_off_last

load_on_last: $(BPF_OBJS)
	./scripts/load_order.sh off-on

load_off_last: $(BPF_OBJS)
	./scripts/load_order.sh on-off

unload:
	./scripts/unload.sh

show:
	./scripts/show_state.sh

clean:
	rm -rf $(OUTPUT)
