ARCH ?= $(shell uname -m)
BPF_ARCH := $(if $(filter x86_64,$(ARCH)),x86,$(if $(filter aarch64 arm64,$(ARCH)),arm64,$(ARCH)))
CLANG ?= $(shell command -v clang 2>/dev/null || echo clang)
CC ?= cc
BPFTOOL ?= bpftool
OUTPUT ?= build
LIBBPF_CFLAGS ?= $(shell pkg-config --cflags libbpf 2>/dev/null)
LIBBPF_LIBS ?= $(shell pkg-config --libs libbpf 2>/dev/null || echo -lbpf)

BPF_SRCS := $(wildcard src/*.bpf.c)
BPF_OBJS := $(patsubst src/%.bpf.c,$(OUTPUT)/%.bpf.o,$(BPF_SRCS))
BPF_CFLAGS := -O2 -g -target bpf -D__TARGET_ARCH_$(BPF_ARCH)
CHAINCTL := $(OUTPUT)/chainctl

.PHONY: all clean doctor load attach_timeout_10 attach_timeout_20 show reset unload verify

all: doctor $(BPF_OBJS) $(CHAINCTL)

doctor:
	@command -v $(BPFTOOL) >/dev/null 2>&1 || { echo "missing bpftool"; exit 1; }
	@command -v $(CLANG) >/dev/null 2>&1 || { echo "missing clang with BPF target support"; exit 1; }
	@command -v $(CC) >/dev/null 2>&1 || { echo "missing C compiler"; exit 1; }
	@test -r /sys/kernel/btf/vmlinux || { echo "missing readable /sys/kernel/btf/vmlinux"; exit 1; }
	@mount | grep -q 'type cgroup2 ' || { echo "cgroup v2 is required"; exit 1; }
	@printf 'CLANG=%s\n' "$(CLANG)"
	@printf 'CC=%s\n' "$(CC)"
	@printf 'BPFTOOL=%s\n' "$(BPFTOOL)"
	@printf 'ARCH=%s BPF_ARCH=%s\n' "$(ARCH)" "$(BPF_ARCH)"

$(OUTPUT):
	mkdir -p $(OUTPUT)

$(OUTPUT)/vmlinux.h: | $(OUTPUT)
	$(BPFTOOL) btf dump file /sys/kernel/btf/vmlinux format c > $@

$(OUTPUT)/%.bpf.o: src/%.bpf.c src/bpf_helpers_min.h src/chainer_state.h $(OUTPUT)/vmlinux.h | $(OUTPUT)
	$(CLANG) $(BPF_CFLAGS) -I$(OUTPUT) -Isrc -c $< -o $@

$(CHAINCTL): tools/chainctl.c | $(OUTPUT)
	$(CC) -O2 -g -Wall -Wextra $(LIBBPF_CFLAGS) $< -o $@ $(LIBBPF_LIBS) -lelf -lz

load: all
	./scripts/load_chainer.sh

attach_timeout_10: all
	./scripts/attach_ext.sh $${SLOT:-1} build/timeout_10.bpf.o timeout_10

attach_timeout_20: all
	./scripts/attach_ext.sh $${SLOT:-2} build/timeout_20.bpf.o timeout_20

show: all
	./scripts/show_state.sh

reset: all
	./scripts/reset_state.sh

unload:
	./scripts/unload.sh

verify: all
	./scripts/verify.sh

clean:
	rm -rf $(OUTPUT)
