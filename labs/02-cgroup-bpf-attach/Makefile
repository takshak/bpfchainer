ARCH ?= $(shell uname -m)
BPF_ARCH := $(if $(filter x86_64,$(ARCH)),x86,$(if $(filter aarch64 arm64,$(ARCH)),arm64,$(ARCH)))
AUTO_CLANG := $(shell \
	if command -v clang >/dev/null 2>&1; then \
		command -v clang; \
	elif command -v clang-21 >/dev/null 2>&1; then \
		command -v clang-21; \
	elif command -v clang-19 >/dev/null 2>&1; then \
		command -v clang-19; \
	elif command -v clang-17 >/dev/null 2>&1; then \
		command -v clang-17; \
	elif command -v clang-15 >/dev/null 2>&1; then \
		command -v clang-15; \
	else \
		for candidate in \
			/usr/lib/llvm-21/bin/clang \
			/usr/lib/llvm-19/bin/clang \
			/usr/lib/llvm-17/bin/clang \
			/usr/lib/llvm-15/bin/clang \
			/opt/homebrew/opt/llvm/bin/clang \
			/opt/local/libexec/llvm-21/bin/clang \
			/opt/local/libexec/llvm-19/bin/clang \
			/opt/local/libexec/llvm-17/bin/clang \
			/opt/local/libexec/llvm-15/bin/clang; do \
			if [ -x "$$candidate" ]; then \
				echo "$$candidate"; \
				break; \
			fi; \
		done; \
	fi)
CLANG ?= $(if $(AUTO_CLANG),$(AUTO_CLANG),clang)
BPFTOOL ?= bpftool
OUTPUT ?= build

BPF_SRCS := $(wildcard src/*.bpf.c)
BPF_OBJS := $(patsubst src/%.bpf.c,$(OUTPUT)/%.bpf.o,$(BPF_SRCS))
BPF_CFLAGS := -O2 -g -target bpf -D__TARGET_ARCH_$(BPF_ARCH)

.PHONY: all clean doctor load unload show verify

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

load: $(OUTPUT)/cgroup_connect4.bpf.o
	./scripts/load.sh $(OUTPUT)/cgroup_connect4.bpf.o

unload:
	./scripts/unload.sh

show:
	./scripts/show_state.sh

verify: $(OUTPUT)/cgroup_connect4.bpf.o
	CLANG="$(CLANG)" ./scripts/verify.sh $(OUTPUT)/cgroup_connect4.bpf.o

clean:
	rm -rf $(OUTPUT)
