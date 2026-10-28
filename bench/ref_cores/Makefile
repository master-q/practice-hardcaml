# Reference cores from the riscv-ice40 survey, for comparison with our
# rv32 core (results: docs/BENCHMARKS.md). Needs network access for fetch.
#   make area        core-only synthesis area, iCE40 and ECP5 (Markdown table)
#   make dhrystone   sw/dhrystone_sim.bin on the reference cores (iverilog)

all: area dhrystone

fetch:
	./fetch.sh

area: fetch
	./area.sh

dhrystone: fetch
	./dhrystone.sh

clean:
	rm -rf build

.PHONY: all fetch area dhrystone clean
