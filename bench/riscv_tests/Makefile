# riscv-tests (self-checking, `p` environment) on the golden model (#25):
# the independent check for the model's user-level I, M and A behaviour.
# Privilege (rv32mi/rv32si) and virtual-memory (`v`) groups follow as the
# model gains S/U modes and Sv32. Needs network access the first time.
ROOT := $(abspath ../..)
RUN := $(ROOT)/_build/default/bench/riscv_tests/run.exe
GROUPS := rv32ui rv32um rv32ua
MARCH := rv32ima_zicsr_zifencei

all: run

fetch:
	./fetch.sh

build: fetch
	@for g in $(GROUPS) selftest; do ./build.sh $$g $(MARCH) build/$$g || exit 1; done

run: build
	cd $(ROOT) && dune build ./bench/riscv_tests/run.exe
	@if $(RUN) build/selftest > /dev/null; \
	  then echo "FAIL: riscv-tests runner accepted a failing test" >&2; exit 1; \
	  else echo "OK: riscv-tests runner rejects a failing test"; fi
	$(RUN) $(addprefix build/,$(GROUPS))

clean:
	rm -rf build

.PHONY: all fetch build run clean
