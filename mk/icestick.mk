# Shared HardCaml -> Yosys -> nextpnr -> icepack flow for iCEstick projects.
#
# A project Makefile sets PROJECT (its path from the repository root, e.g.
# designs/blink), EXPECT_BRAM (number of SB_RAM40_4K blocks the design must
# use), MAX_LC (logic-cell budget; the build fails above it), optionally
# FIRMWARE (a dune target, e.g. sw/echo.bin), and includes this file. The project provides bin/main.exe
# (prints Verilog for module `top`) and icestick.pcf.
#
#   make           build/top.bin, then check the BRAM count (S3)
#   make test      S1: Cyclesim tests of this project (dune test)
#   make verilate  S2: the same benches on Verilator (if verilator/ exists)
#   make names     naming discipline on the generated Verilog (S3)
#   make netlist-sim  post-synthesis board simulation (if netlist/ exists)
#   make prog      flash build/top.bin to an attached iCEstick (S4)
#   make clean

ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD    := build
EXE      := $(ROOT)/_build/default/$(PROJECT)/bin/main.exe
FW_FILE  := $(if $(FIRMWARE),$(ROOT)/_build/default/$(FIRMWARE))
HWSRCS   := $(shell find src bin $(ROOT)/ip $(ROOT)/models -name '*.ml' -o -name dune 2>/dev/null)
SWSRCS   := $(shell find $(ROOT)/sw -type f 2>/dev/null)

all: $(BUILD)/top.bin resources

# Hardware and firmware are separate targets: a firmware change must not
# re-run synthesis.
$(EXE): $(HWSRCS)
	cd $(ROOT) && dune build ./$(PROJECT)/bin/main.exe

ifneq ($(FIRMWARE),)
$(FW_FILE): $(SWSRCS)
	cd $(ROOT) && dune build ./$(FIRMWARE)
endif

ifeq ($(FIRMWARE),)
$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
	@$(ROOT)/scripts/versions.sh > $(BUILD)/versions.txt
	$(EXE) > $@

PNR_ASC := $(BUILD)/top.asc
else
# Firmware designs (see designs/mcu/bin/main.ml): synthesise once with
# random placeholder RAM contents, then let icebram put the firmware into
# the placed and routed bitstream. After a firmware-only change, make
# re-runs just the last steps (about a second instead of a full build).
$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
	@$(ROOT)/scripts/versions.sh > $(BUILD)/versions.txt
	$(EXE) placeholder $(BUILD) > $@

PNR_ASC := $(BUILD)/placeholder.asc

$(BUILD)/firmware_b0.hex: $(FW_FILE) $(EXE)
	@mkdir -p $(BUILD)
	$(EXE) hex $(FW_FILE) $(BUILD)

# Swap each RAM lane, then check that only BRAM contents changed: the
# logic and routing must be byte-identical to the placeholder bitstream.
# (Swapping back is not a usable check: firmware has long runs of zeros,
# which icebram cannot locate unambiguously.)
$(BUILD)/top.asc: $(BUILD)/placeholder.asc $(BUILD)/firmware_b0.hex
	cp $< $@.tmp
	for b in 0 1 2 3; do \
	  icebram $(BUILD)/placeholder_b$$b.hex $(BUILD)/firmware_b$$b.hex < $@.tmp > $@.swap && \
	  mv $@.swap $@.tmp || exit 1; \
	done
	$(ROOT)/scripts/strip_ram_data.sh $< > $@.logic_before
	$(ROOT)/scripts/strip_ram_data.sh $@.tmp > $@.logic_after
	cmp -s $@.logic_before $@.logic_after || { echo "ERROR: icebram changed more than BRAM contents" >&2; exit 1; }
	rm -f $@.logic_before $@.logic_after
	mv $@.tmp $@

# Strong check (make ci): the swapped bitstream must be byte-identical to
# one synthesised directly with the firmware in the RAM.
icebram-check: $(BUILD)/top.asc $(FW_FILE)
	mkdir -p $(BUILD)/direct
	$(EXE) verilog $(FW_FILE) $(BUILD)/direct > $(BUILD)/direct.v
	yosys -q -p 'synth_ice40 -top top -json $(BUILD)/direct.json' $(BUILD)/direct.v
	nextpnr-ice40 -q --hx1k --package tq144 --freq 12 \
	  --json $(BUILD)/direct.json --pcf icestick.pcf --asc $(BUILD)/direct.asc
	cmp $(BUILD)/top.asc $(BUILD)/direct.asc && echo "OK: icebram bitstream equals direct synthesis"
endif

$(BUILD)/top.json: $(BUILD)/top.v
	yosys -q -l $(BUILD)/yosys.log -p 'synth_ice40 -top top -json $@' $<

$(PNR_ASC): $(BUILD)/top.json icestick.pcf
	nextpnr-ice40 -q -l $(BUILD)/nextpnr.log --hx1k --package tq144 --freq 12 \
	  --json $< --pcf icestick.pcf --asc $@
	@grep -m1 'ICESTORM_LC:' $(BUILD)/nextpnr.log
	@grep -m1 'ICESTORM_RAM:' $(BUILD)/nextpnr.log
	@grep 'Max frequency' $(BUILD)/nextpnr.log | tail -1

$(BUILD)/top.bin: $(BUILD)/top.asc
	icepack $< $@

resources: $(PNR_ASC)
	@$(ROOT)/scripts/check_resources.sh $(BUILD)/nextpnr.log $(EXPECT_BRAM) $(MAX_LC)

# Board-level simulation of the exact generated Verilog with the firmware
# (designs that provide tb_top.v): catches problems in the board top level
# and in RAM initialisation that the S1/S2 benches, which use the load
# port, cannot see.
board-sim: $(FW_FILE) $(EXE)
	@mkdir -p $(BUILD)/direct
	$(EXE) verilog $(FW_FILE) $(BUILD)/direct > $(BUILD)/direct.v
	iverilog -g2012 -o $(BUILD)/board_sim.vvp tb_top.v $(BUILD)/direct.v
	vvp -n $(BUILD)/board_sim.vvp | tr -d '\r' | tee $(BUILD)/board_sim.log
	@grep -q '^\[tb\] PASS' $(BUILD)/board_sim.log

# Board-level post-synthesis stage (designs that provide netlist/, #20):
# the same Verilog as board-sim, synthesised by Yosys and simulated as an
# iCE40 netlist in HardCaml, firmware only in the block RAM INIT values.
netlist-sim: $(FW_FILE) $(EXE)
	@mkdir -p $(BUILD)/direct
	$(EXE) verilog $(FW_FILE) $(BUILD)/direct > $(BUILD)/direct.v
	cd $(ROOT) && dune build ./$(PROJECT)/netlist/main.exe
	$(ROOT)/_build/default/$(PROJECT)/netlist/main.exe $(BUILD)/direct.v $(BUILD)/netlist_sim

test:
	cd $(ROOT) && dune test ./$(PROJECT)

verilate:
	@if [ -d verilator ]; then \
	  mkdir -p $(BUILD) && cd $(ROOT) && \
	  dune build ./$(PROJECT)/verilator/main.exe $(if $(FIRMWARE),./$(FIRMWARE)) && \
	  ./_build/default/$(PROJECT)/verilator/main.exe $(FW_FILE) > $(PROJECT)/$(BUILD)/verilator.log; \
	else echo "$(PROJECT): no verilator stage"; fi

names: $(BUILD)/top.v
	$(ROOT)/scripts/check_names.sh $<

# Flashing requires every S3 check (B-0015) and, where the design has
# them, the board simulation and the post-synthesis board simulation.
prog: all names $(if $(wildcard tb_top.v),board-sim) $(if $(wildcard netlist),netlist-sim)
	iceprog $(BUILD)/top.bin

clean:
	rm -rf $(BUILD)

.PHONY: all resources icebram-check board-sim netlist-sim test verilate names prog clean
