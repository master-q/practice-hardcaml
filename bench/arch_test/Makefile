# RISC-V architectural tests (riscv-arch-test 2.7.4, RV32I) on the rv32
# core in Cyclesim, in lockstep with the golden model, signatures compared
# with the reference signatures shipped with the tests. Issue #17.
# Needs network access the first time (fetch).
ROOT := $(abspath ../..)

all: run

fetch:
	./fetch.sh

build: fetch
	./build.sh

RUN := $(ROOT)/_build/default/bench/arch_test/run.exe

run: build selftest
	$(RUN) build/tests

# The runner must fail on a wrong signature word.
selftest: build
	cd $(ROOT) && dune build ./bench/arch_test/run.exe
	rm -rf build/neg && mkdir -p build/neg
	cp build/tests/add-01.* build/neg/ && : > build/neg/skipped.txt
	sed -i '5s/.*/deadbeef/' build/neg/add-01.reference_output
	! $(RUN) build/neg > /dev/null
	@echo "OK: arch-test runner rejects a wrong signature"

clean:
	rm -rf build

.PHONY: all fetch build run selftest clean
