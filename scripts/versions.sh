#!/usr/bin/env bash
# Print the versions of every tool whose output ends up in a bitstream or a
# measured number. Synthesis results (LC counts) and firmware (instruction
# counts) differ between tool releases (BUGS.md B-0013, B-0015), so builds
# record this next to their logs and CI prints it.
v() { printf '%-26s %s\n' "$1" "$( ("${@:2}") 2>&1 | head -n1 || echo missing)"; }
root=$(cd "$(dirname "$0")/.." && pwd)
printf '%-26s %s\n' "pinned OSS CAD Suite" "$(sed -n 's/^OSS_CAD_SUITE_DATE=//p' "$root/toolchain/oss-cad-suite.conf")"
printf '%-26s %s\n' "OSS CAD Suite on PATH" "$(command -v yosys | sed -n 's#.*/oss-cad-suite-\([^/]*\)/bin/yosys#\1#p')"
v yosys yosys -V
v nextpnr-ice40 nextpnr-ice40 --version
v nextpnr-ecp5 nextpnr-ecp5 --version
v riscv-none-elf-gcc riscv-none-elf-gcc --version
v riscv32-linux-gcc riscv32-buildroot-linux-musl-gcc --version
v ocaml ocaml -version
v hardcaml sh -c "opam list --installed --short --columns=version hardcaml 2>/dev/null"
v verilator verilator --version
v iverilog sh -c "iverilog -V 2>&1"
v z3 z3 --version
