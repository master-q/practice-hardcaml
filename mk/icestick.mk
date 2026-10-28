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
	$(EXE) > $@

PNR_ASC := $(BUILD)/top.asc
else
# Firmware designs (see designs/mcu/bin/main.ml): synthesise once with
# random placeholder RAM contents, then let icebram put the firmware into
# the placed and routed bitstream. After a firmware-only change, make
# re-runs just the last steps (about a second instead of a full build).
$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
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

prog: $(BUILD)/top.bin
	iceprog $<

clean:
	rm -rf $(BUILD)

.PHONY: all resources icebram-check test verilate names prog clean
