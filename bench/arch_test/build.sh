#!/usr/bin/env bash
# Build every RV32I architectural test into build/tests/NAME.bin plus
# NAME.sig ("BEGIN END" signature addresses in hex) for run.exe.
set -euo pipefail
src=build/src/riscv-test-suite
out=build/tests
mkdir -p $out
: > $out/skipped.txt
for s in $src/rv32i_m/I/src/*.S; do
  name=$(basename "$s" .S)
  if [ ! -f "$src/rv32i_m/I/references/$name.reference_output" ]; then
    echo "$name: no reference signature in 2.7.4" >> $out/skipped.txt
    continue
  fi
  # Some 2.7.4 tests use assembler syntax that newer binutils reject
  # (jalr-01: `la x0, 5b`); they are listed in skipped.txt, not patched.
  if ! riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
    -mno-relax -Wl,--no-warn-rwx-segments -DXLEN=32 \
    -I. -I$src/env -T link.ld -o $out/$name.elf "$s" 2> $out/$name.log; then
    echo "$name: does not assemble ($(grep -m1 -i error $out/$name.log | sed 's/.*Error: //'))" >> $out/skipped.txt
    continue
  fi
  riscv-none-elf-objcopy -O binary $out/$name.elf $out/$name.bin
  riscv-none-elf-nm $out/$name.elf \
    | awk '$3 == "begin_signature" { b = $1 } $3 == "end_signature" { e = $1 } END { print b, e }' \
    > $out/$name.sig
  cp "$src/rv32i_m/I/references/$name.reference_output" $out/$name.reference_output
done
ls $out/*.bin | wc -l
