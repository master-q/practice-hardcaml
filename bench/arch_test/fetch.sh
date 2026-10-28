#!/usr/bin/env bash
# Fetch the RISC-V architectural tests (riscv-non-isa/riscv-arch-test,
# tag 2.7.4: RV32I tests with reference signatures produced by independent
# simulators) into build/src. Not committed; see the repository's licenses
# (COPYING.BSD / COPYING.APACHE / COPYING.CC).
set -euo pipefail
d=build/src
tag=2.7.4
if [ -f "$d/.fetched-$tag" ]; then exit 0; fi
rm -rf "$d"
git init -q "$d"
git -C "$d" remote add origin https://github.com/riscv-non-isa/riscv-arch-test.git
git -C "$d" config core.sparseCheckout true
printf '%s\n' riscv-test-suite/rv32i_m/I/ riscv-test-suite/env/ 'COPYING*' > "$d/.git/info/sparse-checkout"
git -C "$d" fetch -q --depth 1 origin tag "$tag"
git -C "$d" checkout -q "$tag"
touch "$d/.fetched-$tag"
