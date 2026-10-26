# Shared HardCaml -> Yosys -> nextpnr -> icepack flow for iCEstick projects.
#
# A project Makefile sets PROJECT (its directory name) and includes this file.
# The project provides bin/main.exe (prints Verilog for module `top`) and
# icestick.pcf. Targets:
#   make         build/top.bin
#   make test    stage 1: Cyclesim tests of this project (dune test)
#   make verilate  stage 2: the same benches on Verilator (if verilator/ exists)
#   make names   naming-discipline check on the generated Verilog
#   make prog    flash build/top.bin to an attached iCEstick (iceprog)
#   make clean

ROOT  := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD := build
EXE   := $(ROOT)/_build/default/$(PROJECT)/bin/main.exe
SRCS  := $(shell find src bin -name '*.ml' -o -name dune 2>/dev/null)

all: $(BUILD)/top.bin

$(EXE): $(SRCS)
	cd $(ROOT) && dune build ./$(PROJECT)/bin/main.exe

$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
	$(EXE) > $@

$(BUILD)/top.json: $(BUILD)/top.v
	yosys -q -l $(BUILD)/yosys.log -p 'synth_ice40 -top top -json $@' $<

$(BUILD)/top.asc: $(BUILD)/top.json icestick.pcf
	nextpnr-ice40 -q -l $(BUILD)/nextpnr.log --hx1k --package tq144 --freq 12 \
	  --json $< --pcf icestick.pcf --asc $@
	@grep -m1 'ICESTORM_LC:' $(BUILD)/nextpnr.log
	@grep 'Max frequency' $(BUILD)/nextpnr.log | tail -1

$(BUILD)/top.bin: $(BUILD)/top.asc
	icepack $< $@

test:
	cd $(ROOT) && dune test ./$(PROJECT)

verilate:
	@if [ -d verilator ]; then \
	  mkdir -p $(BUILD) && cd $(ROOT) && dune build ./$(PROJECT)/verilator/main.exe && \
	  ./_build/default/$(PROJECT)/verilator/main.exe > $(PROJECT)/$(BUILD)/verilator.log; \
	else echo "$(PROJECT): no verilator stage"; fi

names: $(BUILD)/top.v
	$(ROOT)/scripts/check_names.sh $<

prog: $(BUILD)/top.bin
	iceprog $<

clean:
	rm -rf $(BUILD)

.PHONY: all test verilate names prog clean
