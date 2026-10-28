#!/usr/bin/env bash
# Fetch the RISC-V architectural tests (riscv-non-isa/riscv-arch-test,
# tag 2.7.4: RV32I tests with reference signatures produced by independent
# simulators) into build/src. Not committed; see the repository's licenses
# (COPYING.BSD / COPYING.APACHE / COPYING.CC).
set -euo pipefail
d=build/src
tag=2.7.4
# The marker names the test groups fetched, so adding a group refetches.
groups="I M A"
marker="$d/.fetched-$tag-$(echo $groups | tr ' ' '-')"
if [ -f "$marker" ]; then exit 0; fi
rm -rf "$d"
git init -q "$d"
git -C "$d" remote add origin https://github.com/riscv-non-isa/riscv-arch-test.git
git -C "$d" config core.sparseCheckout true
{
  for g in $groups; do echo "riscv-test-suite/rv32i_m/$g/"; done
  printf '%s\n' riscv-test-suite/env/ 'COPYING*'
} > "$d/.git/info/sparse-checkout"
git -C "$d" fetch -q --depth 1 origin tag "$tag"
git -C "$d" checkout -q "$tag"
touch "$marker"
