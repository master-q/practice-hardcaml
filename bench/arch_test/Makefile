# RISC-V architectural tests (riscv-arch-test 2.7.4, RV32I and M) on the rv32
# core in Cyclesim, in lockstep with the golden model, signatures compared
# with the reference signatures shipped with the tests. Issue #17.
# Needs network access the first time (fetch).
ROOT := $(abspath ../..)

all: run

fetch:
	./fetch.sh

build: fetch
	./build.sh I rv32i build/tests
	./build.sh M rv32im build/tests_m

RUN := $(ROOT)/_build/default/bench/arch_test/run.exe

# RV32I on the plain core and the i9 configurations; M on the golden model
# and on the i9 core with M and A (#5).
run: build selftest
	$(RUN) build/tests
	$(RUN) --m build/tests_m

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
