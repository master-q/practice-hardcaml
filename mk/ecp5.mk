# HardCaml -> Yosys -> nextpnr-ecp5 -> ecppack flow for Colorlight i9
# (LFE5U-45F, CABGA381) designs. The counterpart of mk/icestick.mk; the
# project Makefile sets the same variables (PROJECT, EXPECT_BRAM counting
# DP16KD blocks, MAX_LC counting TRELLIS_COMB LUT slots, FIRMWARE) and
# provides bin/main.exe (Mcu_gen.Rtl_init modes) and colorlight_i9.lpf.
#
#   make             build/top.bit, then S3 resource checks
#   make names       naming discipline on the generated Verilog
#   make ecpbram-check   swapped bitstream equals direct synthesis
#   make prog        load build/top.bit into the FPGA (SRAM) over the
#                    ext board's DAPLink (openFPGALoader)
#   make flash       write it to the SPI flash instead
#   make clean

ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
BUILD    ?= build
EXE      := $(ROOT)/_build/default/$(PROJECT)/bin/main.exe
FW_FILE  := $(ROOT)/_build/default/$(FIRMWARE)
HWSRCS   := $(shell find src bin $(ROOT)/ip $(ROOT)/models -name '*.ml' -o -name dune 2>/dev/null)
SWSRCS   := $(shell find $(ROOT)/sw -type f 2>/dev/null)
LPF      := colorlight_i9.lpf
# The system clock in MHz: designs with a PLL print it (`main.exe
# clock-mhz`); nextpnr checks every path against it. The PLL output is
# also derived by nextpnr from the oscillator's FREQUENCY in the LPF.
CLOCK_MHZ = $$($(EXE) clock-mhz 2>/dev/null || echo 25)
PNR      = nextpnr-ecp5 -q --45k --package CABGA381 --speed 6 --freq $(CLOCK_MHZ) --lpf $(LPF)

all: $(BUILD)/top.bit resources

$(EXE): $(HWSRCS)
	cd $(ROOT) && dune build ./$(PROJECT)/bin/main.exe

$(FW_FILE): $(SWSRCS)
	cd $(ROOT) && dune build ./$(FIRMWARE)

# Synthesise once with random placeholder RAM contents; ecpbram puts the
# firmware into the placed and routed configuration (see docs/WORKFLOW.md,
# "Program loading"), so a firmware change needs no synthesis.
$(BUILD)/top.v: $(EXE)
	@mkdir -p $(BUILD)
	@$(ROOT)/scripts/versions.sh > $(BUILD)/versions.txt
	$(EXE) placeholder $(BUILD) > $@

$(BUILD)/top.json: $(BUILD)/top.v
	yosys -q -l $(BUILD)/yosys.log -p 'synth_ecp5 -top top -json $@' $<

$(BUILD)/placeholder.config: $(BUILD)/top.json $(LPF)
	$(PNR) -l $(BUILD)/nextpnr.log --json $< --textcfg $@
	@grep -m1 'TRELLIS_COMB:' $(BUILD)/nextpnr.log
	@grep -m1 'DP16KD:' $(BUILD)/nextpnr.log
	@grep 'Max frequency' $(BUILD)/nextpnr.log | tail -1

$(BUILD)/firmware_b0.hex: $(FW_FILE) $(EXE)
	@mkdir -p $(BUILD)
	$(EXE) hex $(FW_FILE) $(BUILD)

$(BUILD)/top.config: $(BUILD)/placeholder.config $(BUILD)/firmware_b0.hex
	cp $< $@.tmp
	for b in 0 1 2 3; do \
	  ecpbram -i $@.tmp -o $@.swap -f $(BUILD)/placeholder_b$$b.hex -t $(BUILD)/firmware_b$$b.hex && \
	  mv $@.swap $@.tmp || exit 1; \
	done
	$(ROOT)/scripts/strip_ram_data.sh $< > $@.logic_before
	$(ROOT)/scripts/strip_ram_data.sh $@.tmp > $@.logic_after
	cmp -s $@.logic_before $@.logic_after || { echo "ERROR: ecpbram changed more than BRAM contents" >&2; exit 1; }
	rm -f $@.logic_before $@.logic_after
	mv $@.tmp $@

$(BUILD)/top.bit: $(BUILD)/top.config
	ecppack --compress $< $@

resources: $(BUILD)/placeholder.config
	@$(ROOT)/scripts/check_resources.sh $(BUILD)/nextpnr.log $(EXPECT_BRAM) $(MAX_LC)

# Strong check: the bitstream built by swapping must equal one placed and
# routed with the firmware in the RAM from the start. (The textual configs
# differ only in .tile_group headers, see scripts/strip_ram_data.sh.)
ecpbram-check: $(BUILD)/top.bit $(FW_FILE)
	mkdir -p $(BUILD)/direct
	$(EXE) verilog $(FW_FILE) $(BUILD)/direct > $(BUILD)/direct.v
	yosys -q -p 'synth_ecp5 -top top -json $(BUILD)/direct.json' $(BUILD)/direct.v
	$(PNR) --json $(BUILD)/direct.json --textcfg $(BUILD)/direct.config
	ecppack --compress $(BUILD)/direct.config $(BUILD)/direct.bit
	cmp $(BUILD)/top.bit $(BUILD)/direct.bit && echo "OK: ecpbram bitstream equals direct synthesis"

# Board-level simulation of the generated Verilog with a firmware image
# (BOARD_SIM_FIRMWARE, default FIRMWARE) and the project's tb_top.v.
BOARD_SIM_FIRMWARE ?= $(FIRMWARE)
BOARD_SIM_FW_FILE := $(ROOT)/_build/default/$(BOARD_SIM_FIRMWARE)

board-sim: $(EXE) $(SWSRCS)
	cd $(ROOT) && dune build ./$(BOARD_SIM_FIRMWARE)
	@mkdir -p $(BUILD)/board_sim
	$(EXE) verilog $(BOARD_SIM_FW_FILE) $(BUILD)/board_sim > $(BUILD)/board_sim.v
	iverilog -g2012 -DCLOCK_MHZ=$(CLOCK_MHZ) -o $(BUILD)/board_sim.vvp tb_top.v $(if $(wildcard tb_cells.v),tb_cells.v) $(BUILD)/board_sim.v
	vvp -n $(BUILD)/board_sim.vvp | tr -d '\r' | tee $(BUILD)/board_sim.log
	@grep -q '^\[tb\] PASS' $(BUILD)/board_sim.log

# Board-level post-synthesis stage (designs that provide netlist/, #20):
# the generated Verilog with NETLIST_SIM_FIRMWARE in block RAM,
# synthesised with synth_ecp5 and simulated as an ECP5 netlist in
# HardCaml, full start-up hold, firmware only in the DP16KD INITVAL.
NETLIST_SIM_FIRMWARE ?= $(FIRMWARE)
netlist-sim: $(EXE) $(SWSRCS)
	cd $(ROOT) && dune build ./$(NETLIST_SIM_FIRMWARE) ./$(PROJECT)/netlist/main.exe
	@mkdir -p $(BUILD)/netlist_fw
	$(EXE) verilog $(ROOT)/_build/default/$(NETLIST_SIM_FIRMWARE) $(BUILD)/netlist_fw > $(BUILD)/netlist_top.v
	$(ROOT)/_build/default/$(PROJECT)/netlist/main.exe $(BUILD)/netlist_top.v $(BUILD)/netlist_sim

test:
	cd $(ROOT) && dune test ./$(PROJECT)

verilate:
	@echo "$(PROJECT): no verilator stage (the MCU is checked on Verilator in designs/mcu)"

names: $(BUILD)/top.v
	$(ROOT)/scripts/check_names.sh $<

# Loading requires every S3 check and the board simulation to pass.
prog: all names board-sim $(if $(wildcard netlist),netlist-sim)
	openFPGALoader -b colorlight-i9 $(BUILD)/top.bit

flash: all names board-sim $(if $(wildcard netlist),netlist-sim)
	openFPGALoader -b colorlight-i9 -f $(BUILD)/top.bit

clean:
	rm -rf $(BUILD)

.PHONY: all resources ecpbram-check board-sim netlist-sim test verilate names prog flash clean
