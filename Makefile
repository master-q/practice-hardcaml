# Top-level driver for the test ladder (see docs/WORKFLOW.md).
#
#   make            setup + langcheck + test + synth + names  (the per-commit gate)
#   make test       stage 1: Cyclesim and model tests (dune test), seconds
#   make verilate   stage 2: the same benches on Verilator, tens of seconds
#   make synth      stage 3: Yosys + nextpnr for every board project
#   make board-sim  the generated iCEstick Verilog, firmware and UART at pin
#                   level in Icarus Verilog (catches board-top problems);
#                   board-sim-i9 does the same for the i9 (slow, in ci)
#   make names      naming discipline on the generated Verilog
#   make langcheck  ASCII-only policy on all tracked files
#   make selftest   negative tests for the checks themselves
#   make netlist-sim the S1 MCU bench (lockstep) on the Yosys iCE40 netlist,
#                   read back into HardCaml (post-synthesis stage, #20)
#   make arch-test  riscv-arch-test RV32I suite on the core (fetches it once)
#   make ci         everything above, including verilate and icebram-check
#
# The RV32E MCU on an iCEstick (S4, by hand):
#   make mcu        build designs/mcu/build/top.bin (firmware sw/echo.bin)
#   make mcu-prog   build and flash it
#   make mcu-term   open the UART at 115200 baud (TTY=/dev/ttyUSB1)
#
# The RV32I MCU on a Colorlight i9 v7.2 with the ext board (S4, by hand):
#   make i9         build designs/mcu_i9/build/top.bit (firmware: Dhrystone)
#   make i9-prog    build and load it over the ext board's DAPLink
#   make i9-term    open the DAPLink serial port (I9_TTY=/dev/ttyACM0)
# Other designs: make -C designs/<name> prog.

TTY ?= /dev/ttyUSB1
I9_TTY ?= /dev/ttyACM0

BOARD_PROJECTS := designs/blink designs/hello designs/mcu designs/mcu_i9

all: setup langcheck selftest test board-sim netlist-sim synth names

setup:
	@scripts/setup_clone.sh

versions:
	@scripts/versions.sh

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

board-sim:
	$(MAKE) --no-print-directory -C designs/mcu board-sim

# Post-synthesis stage (#20); the second run is its negative test: with
# every LUT complemented the bench must fail.
NETLIST_EXE := _build/default/ip/mcu/netlist/main.exe
netlist-sim:
	dune build ./ip/mcu/netlist/main.exe ./sw/echo_rv32e.bin
	$(NETLIST_EXE) _build/default/sw/echo_rv32e.bin build/netlist_sim
	@if $(NETLIST_EXE) --invert-luts _build/default/sw/echo_rv32e.bin build/netlist_sim >/dev/null 2>&1; \
	  then echo "FAIL: netlist-sim accepted a netlist with inverted LUTs" >&2; exit 1; \
	  else echo "OK: netlist-sim rejects a netlist with inverted LUTs"; fi

# riscv-arch-test (RV32I, reference signatures) on the core; fetches the
# tests on first use. Issue #17.
arch-test:
	$(MAKE) --no-print-directory -C bench/arch_test run

# The i9 board simulation takes about 2 minutes (Icarus, UART output).
board-sim-i9:
	$(MAKE) --no-print-directory -C designs/mcu_i9 board-sim

names:
	@for p in $(BOARD_PROJECTS); do $(MAKE) --no-print-directory -C $$p names || exit 1; done

ci: langcheck selftest test arch-test board-sim netlist-sim board-sim-i9 verilate synth names icebram-check ecpbram-check

mcu:
	$(MAKE) -C designs/mcu

mcu-prog:
	$(MAKE) -C designs/mcu prog

i9:
	$(MAKE) -C designs/mcu_i9

i9-prog:
	$(MAKE) -C designs/mcu_i9 prog

i9-term:
	picocom -b 115200 $(I9_TTY)

ecpbram-check:
	$(MAKE) -C designs/mcu_i9 ecpbram-check

icebram-check:
	$(MAKE) -C designs/mcu icebram-check

mcu-term:
	picocom -b 115200 $(TTY)

clean:
	dune clean
	@for p in $(BOARD_PROJECTS); do $(MAKE) --no-print-directory -C $$p clean; done

.PHONY: versions arch-test board-sim board-sim-i9 netlist-sim mcu mcu-prog mcu-term i9 i9-prog i9-term ecpbram-check icebram-check all setup langcheck selftest test verilate synth names ci clean
