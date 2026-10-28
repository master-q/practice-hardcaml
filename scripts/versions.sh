#!/usr/bin/env bash
# Print the versions of every tool whose output ends up in a bitstream or a
# measured number. Synthesis results (LC counts) and firmware (instruction
# counts) differ between tool releases (BUGS.md B-0013, B-0015), so builds
# record this next to their logs and CI prints it.
v() { printf '%-26s %s\n' "$1" "$( ("${@:2}") 2>&1 | head -n1 || echo missing)"; }
v yosys yosys -V
v nextpnr-ice40 nextpnr-ice40 --version
v nextpnr-ecp5 nextpnr-ecp5 --version
v riscv64-unknown-elf-gcc riscv64-unknown-elf-gcc --version
v ocaml ocaml -version
v hardcaml sh -c "opam list --installed --short --columns=version hardcaml 2>/dev/null"
v verilator verilator --version
v iverilog sh -c "iverilog -V 2>&1"
