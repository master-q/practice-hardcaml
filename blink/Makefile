# iCEstick (iCE40HX1K, TQ144) LED blinker written in HardCaml.
#   make        -> build/top.bin
#   make prog   -> write to iCEstick with iceprog
BUILD := build

all: $(BUILD)/top.bin

$(BUILD)/top.v: blink.ml dune
	@mkdir -p $(BUILD)
	dune build ./blink.exe
	dune exec --no-build ./blink.exe > $@

$(BUILD)/top.json: $(BUILD)/top.v
	yosys -q -p 'synth_ice40 -top top -json $@' $<

$(BUILD)/top.asc: $(BUILD)/top.json icestick.pcf
	nextpnr-ice40 --hx1k --package tq144 --freq 12 --json $< --pcf icestick.pcf --asc $@

$(BUILD)/top.bin: $(BUILD)/top.asc
	icepack $< $@

prog: $(BUILD)/top.bin
	iceprog $<

clean:
	rm -rf $(BUILD)

.PHONY: all prog clean
