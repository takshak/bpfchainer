ARCH ?= $(shell uname -m)
BPF_ARCH := $(if $(filter x86_64,$(ARCH)),x86,$(if $(filter aarch64 arm64,$(ARCH)),arm64,$(ARCH)))
CLANG ?= $(shell command -v clang 2>/dev/null || echo clang)
BPFTOOL ?= bpftool
OUTPUT ?= build

BPF_SRCS := $(wildcard src/*.bpf.c)
BPF_OBJS := $(patsubst src/%.bpf.c,$(OUTPUT)/%.bpf.o,$(BPF_SRCS))
BPF_CFLAGS := -O2 -g -target bpf -D__TARGET_ARCH_$(BPF_ARCH)

.PHONY: all clean doctor load_a_last load_b_last unload verify verify_a_last verify_b_last

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

$(OUTPUT)/%.bpf.o: src/%.bpf.c src/bpf_helpers_min.h $(OUTPUT)/vmlinux.h | $(OUTPUT)
	$(CLANG) $(BPF_CFLAGS) -I$(OUTPUT) -Isrc -c $< -o $@

verify_a_last: $(BPF_OBJS)
	./scripts/verify_order.sh b-a

verify_b_last: $(BPF_OBJS)
	./scripts/verify_order.sh a-b

verify: verify_a_last verify_b_last

load_a_last: $(BPF_OBJS)
	./scripts/load_order.sh b-a

load_b_last: $(BPF_OBJS)
	./scripts/load_order.sh a-b

unload:
	./scripts/unload.sh

clean:
	rm -rf $(OUTPUT)
