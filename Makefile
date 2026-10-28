# Top-level driver for the test ladder (see docs/WORKFLOW.md).
#
#   make            setup + langcheck + test + synth + names  (the per-commit gate)
#   make test       stage 1: Cyclesim and model tests (dune test), seconds
#   make verilate   stage 2: the same benches on Verilator, tens of seconds
#   make synth      stage 3: Yosys + nextpnr for every board project
#   make names      naming discipline on the generated Verilog
#   make langcheck  ASCII-only policy on all tracked files
#   make selftest   negative tests for the checks themselves
#   make ci         everything above, including verilate and icebram-check
#
# The RV32E MCU on an iCEstick (S4, by hand):
#   make mcu        build designs/mcu/build/top.bin (firmware sw/echo.bin)
#   make mcu-prog   build and flash it
#   make mcu-term   open the UART at 115200 baud (TTY=/dev/ttyUSB1)
# Other designs: make -C designs/<name> prog.

TTY ?= /dev/ttyUSB1

BOARD_PROJECTS := designs/blink designs/hello designs/mcu

all: setup langcheck selftest test synth names

setup:
	@scripts/setup_clone.sh

langcheck:
	@scripts/check_ascii.sh

selftest:
	@scripts/selftest.sh

test:
	dune build @runtest

verilate:
	@for p in $(BOARD_PROJECTS); do $(MAKE) --no-print-directory -C $$p verilate || exit 1; done

synth:
	@for p in $(BOARD_PROJECTS); do echo "== $$p"; $(MAKE) --no-print-directory -C $$p all || exit 1; done

names:
	@for p in $(BOARD_PROJECTS); do $(MAKE) --no-print-directory -C $$p names || exit 1; done

ci: langcheck selftest test verilate synth names icebram-check

mcu:
	$(MAKE) -C designs/mcu

mcu-prog:
	$(MAKE) -C designs/mcu prog

icebram-check:
	$(MAKE) -C designs/mcu icebram-check

mcu-term:
	picocom -b 115200 $(TTY)

clean:
	dune clean
	@for p in $(BOARD_PROJECTS); do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: mcu mcu-prog mcu-term icebram-check all setup langcheck selftest test verilate synth names ci clean
