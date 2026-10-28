#!/usr/bin/env bash
# Build one riscv-tests group with the `p` environment into OUT/NAME.bin and
# NAME.tohost (tohost address in hex).
#
#   build.sh GROUP MARCH OUT     e.g. build.sh rv32ua rv32ima_zicsr build/rv32ua
set -euo pipefail
group=$1 march=$2 out=$3
src=build/src
mkdir -p $out
n=0
: > $out/skipped.txt
if [ "$group" = selftest ]; then sources=selftest_fail.S; else sources=$src/isa/$group/*.S; fi
for s in $sources; do
  name=$group-p-$(basename "$s" .S)
  # Misaligned loads and stores trap on this design (the model and the
  # core; Linux emulates them in its trap handler). ma_data needs them to
  # work or an emulating handler in the test environment.
  if [ "$name" = rv32ui-p-ma_data ]; then
    echo "$name: needs misaligned access support (traps here)" >> $out/skipped.txt
    continue
  fi
  riscv-none-elf-gcc -march=$march -mabi=ilp32 -static -nostdlib -nostartfiles \
    -mno-relax -Wl,--no-warn-rwx-segments \
    -I$src/env/p -I$src/isa/macros/scalar -T link.ld -o $out/$name.elf "$s"
  riscv-none-elf-objcopy -O binary $out/$name.elf $out/$name.bin
  riscv-none-elf-nm $out/$name.elf | awk '$3 == "tohost" { print $1 }' > $out/$name.tohost
  n=$((n + 1))
done
echo "$group: $n tests"
