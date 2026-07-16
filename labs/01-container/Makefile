.PHONY: verify create enter exec destroy clean

NAME ?= c1

verify:
	./verify.sh

create:
	./container-runtime.sh create $(NAME)

enter:
	./container-runtime.sh enter $(NAME)

exec:
	@test -n "$(CMD)" || { echo 'usage: sudo make exec NAME=c1 CMD="hostname"'; exit 1; }
	./container-runtime.sh exec $(NAME) $(CMD)

destroy:
	./container-runtime.sh destroy $(NAME)

clean:
	./container-runtime.sh destroy $(NAME) 2>/dev/null || true
