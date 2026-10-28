# Shared HardCaml -> Yosys -> nextpnr -> icepack flow for iCEstick projects.
#
# A project Makefile sets PROJECT (its path from the repository root, e.g.
# designs/blink), EXPECT_BRAM (number of SB_RAM40_4K blocks the design must
# use), MAX_LC (logic-cell budget; the build fails above it), optionally FIRMWARE (a dune target passed to the generator, e.g.
# sw/echo.bin), and includes this file. The project provides bin/main.exe
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
SRCS     := $(shell find src bin -name '*.ml' -o -name dune 2>/dev/null)
DEPSRCS  := $(shell find $(ROOT)/ip $(ROOT)/sw -name '*.ml' -o -name dune -o -name '*.c' -o -name '*.h' -o -name '*.S' -o -name '*.ld' 2>/dev/null)

all: $(BUILD)/top.bin resources

$(EXE): $(SRCS) $(DEPSRCS)
	cd $(ROOT) && dune build ./$(PROJECT)/bin/main.exe $(if $(FIRMWARE),./$(FIRMWARE))

$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
	$(EXE) $(FW_FILE) > $@

$(BUILD)/top.json: $(BUILD)/top.v
	yosys -q -l $(BUILD)/yosys.log -p 'synth_ice40 -top top -json $@' $<

$(BUILD)/top.asc: $(BUILD)/top.json icestick.pcf
	nextpnr-ice40 -q -l $(BUILD)/nextpnr.log --hx1k --package tq144 --freq 12 \
	  --json $< --pcf icestick.pcf --asc $@
	@grep -m1 'ICESTORM_LC:' $(BUILD)/nextpnr.log
	@grep -m1 'ICESTORM_RAM:' $(BUILD)/nextpnr.log
	@grep 'Max frequency' $(BUILD)/nextpnr.log | tail -1

$(BUILD)/top.bin: $(BUILD)/top.asc
	icepack $< $@

resources: $(BUILD)/top.asc
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

.PHONY: all resources test verilate names prog clean
