#!/usr/bin/env bash
# Core-only synthesis area of the reference cores (configured as in the
# riscv-ice40 survey) and of our rv32 core, for iCE40 and ECP5.
# Run from bench/ref_cores after ./fetch.sh; prints a Markdown table.
#
# Counts are Yosys `stat` cells after synth_ice40 / synth_ecp5 (no place
# and route): LUT4, carry cells (SB_CARRY / CCU2C, one CCU2C = 2 LUT
# slots), flip-flops, and RAM (SB_RAM40_4K / DP16KD / TRELLIS_DPR16X4).
set -euo pipefail
src=build/src
s=$src/riscv-ice40/cores
out=build/area
mkdir -p $out

root=$(git rev-parse --show-toplevel)
(cd "$root" && dune build ./ip/rv32/bin/core_verilog.exe 2>/dev/null)
"$root/_build/default/ip/rv32/bin/core_verilog.exe" rv32i > $out/rv32i.v
"$root/_build/default/ip/rv32/bin/core_verilog.exe" rv32e > $out/rv32e.v

haz=$src/hazard3/hdl
haz_src=$(for f in hazard3_decode.v hazard3_triggers.v hazard3_instr_decompress.v hazard3_csr.v \
  hazard3_power_ctrl.v arith/hazard3_onehot_priority.v arith/hazard3_shift_barrel.v \
  arith/hazard3_priority_encode.v arith/hazard3_onehot_encode.v \
  arith/hazard3_onehot_priority_dynamic.v arith/hazard3_muldiv_seq.v arith/hazard3_alu.v \
  arith/hazard3_mul_fast.v arith/hazard3_branchcmp.v hazard3_regfile_1w2r.v hazard3_core.v \
  hazard3_irq_ctrl.v hazard3_frontend.v hazard3_pmp.v; do printf '%s ' $haz/$f; done)

# name | yosys read commands | top
cores=(
  "rv32 (this repo, RV32I)|read_verilog $out/rv32i.v|rv32_core"
  "rv32 (this repo, RV32E)|read_verilog $out/rv32e.v|rv32_core"
  "PicoRV32 (ENABLE_COUNTERS=1)|read_verilog $src/picorv32/picorv32.v; chparam -set ENABLE_COUNTERS 1 picorv32|picorv32"
  "FemtoRV32 Quark|read_verilog $src/femtorv/FemtoRV/RTL/PROCESSOR/femtorv32_quark.v|FemtoRV32"
  "Hazard3 (riscv-ice40 config)|read_verilog -I $s/hazard3-soc -I $haz -I $haz/arith $haz_src|hazard3_core"
)

cell() { grep -E "^\s+$1\s" "$2" | awk '{s += $2} END {print s + 0}'; }

echo "| Core | iCE40 LUT4 | SB_CARRY | FF | SB_RAM40_4K | ECP5 LUT4 | CCU2C | FF | DP16KD | DPR16X4 |"
echo "|------|-----------:|---------:|---:|------------:|----------:|------:|---:|-------:|--------:|"
n=0
for c in "${cores[@]}"; do
  IFS='|' read -r name read top <<< "$c"
  n=$((n + 1))
  tag=core$n
  yosys -q -p "$read; synth_ice40 -top $top; tee -q -o $out/$tag.ice40.stat stat" > $out/$tag.ice40.log 2>&1
  yosys -q -p "$read; synth_ecp5 -top $top; tee -q -o $out/$tag.ecp5.stat stat" > $out/$tag.ecp5.log 2>&1
  i=$out/$tag.ice40.stat e=$out/$tag.ecp5.stat
  echo "| $name | $(cell SB_LUT4 $i) | $(cell SB_CARRY $i) | $(cell 'SB_DFF[A-Z]*' $i) | $(cell SB_RAM40_4K $i) |" \
       "$(cell LUT4 $e) | $(cell CCU2C $e) | $(cell TRELLIS_FF $e) | $(cell DP16KD $e) | $(cell TRELLIS_DPR16X4 $e) |"
done
