#!/usr/bin/env bash
# Run the MCU's Dhrystone image (sw/dhrystone_sim.bin, 50 runs) on the
# reference cores in Icarus Verilog and print their harness output. Run
# from bench/ref_cores after ./fetch.sh.
set -euo pipefail
root=$(git rev-parse --show-toplevel)
src=build/src
(cd "$root" && dune build ./sw/dhrystone_sim.bin 2>/dev/null)
mkdir -p build/sim
# One 32-bit little-endian word per line, padded to the RAM size.
# (`yes` ends with SIGPIPE when head has enough, hence `|| true`.)
{ od -An -tx4 -v "$root/_build/default/sw/dhrystone_sim.bin" | tr -s ' ' '\n' | grep .
  yes 00000000 || true; } | head -n 16384 > build/sim/firmware.hex
hex='"build/sim/firmware.hex"'
run() { # name tb sources...
  local name=$1; shift
  iverilog -g2012 -DFIRMWARE_HEX="$hex" -o build/sim/$name.vvp "$@"
  echo "== $name"
  vvp -n build/sim/$name.vvp | tr -d '\r'
}
run picorv32-1wait tb_picorv32.v $src/picorv32/picorv32.v
run picorv32-0wait tb_picorv32_zw.v $src/picorv32/picorv32.v
run femtorv tb_femtorv.v $src/femtorv/FemtoRV/RTL/PROCESSOR/femtorv32_quark.v
