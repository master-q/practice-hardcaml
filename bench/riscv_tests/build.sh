#!/usr/bin/env bash
# Build one riscv-tests group with the `p` environment into OUT/NAME.bin and
# NAME.tohost (tohost address in hex).
#
#   build.sh GROUP MARCH OUT [ENV]   e.g. build.sh rv32ua rv32ima_zicsr build/rv32ua
#
# ENV is p (default: the test runs bare) or v (the test runs in U-mode
# under riscv-tests' small S-mode kernel with Sv32 demand paging).
set -euo pipefail
group=$1 march=$2 out=$3 env=${4:-p}
src=build/src
mkdir -p $out
n=0
: > $out/skipped.txt
if [ "$group" = selftest ]; then sources=selftest_fail.S; else sources=$src/isa/$group/*.S; fi
for s in $sources; do
  name=$group-$env-$(basename "$s" .S)
  # Misaligned loads and stores trap on this design (the model and the
  # core; Linux emulates them in its trap handler). ma_data needs them to
  # work or an emulating handler in the test environment.
  if [ "$name" = rv32ui-$env-ma_data ]; then
    echo "$name: needs misaligned access support (traps here)" >> $out/skipped.txt
    continue
  fi
  # No PMP entries are implemented (the PMP CSRs read as zero, which the
  # privileged spec allows); this test needs at least one.
  if [ "$name" = rv32mi-p-pmpaddr ]; then
    echo "$name: needs PMP entries (none implemented)" >> $out/skipped.txt
    continue
  fi
  if [ "$env" = p ]; then
    riscv-none-elf-gcc -march=$march -mabi=ilp32 -static -nostdlib -nostartfiles \
      -mno-relax -Wl,--no-warn-rwx-segments \
      -I$src/env/p -I$src/isa/macros/scalar -T link.ld -o $out/$name.elf "$s"
  else
    # As riscv-tests' isa/Makefile builds the v variants. env/v/vm.c embeds
    # one `fssr` encoding (to recognise FP tests on non-FP hardware), so
    # the assembler needs F; the generated code is integer only.
    entropy=0x$(echo "$name" | md5sum | cut -c 1-7)
    vmarch=$(echo "$march" | sed 's/^rv32ima/rv32imaf/')
    riscv-none-elf-gcc -march=$vmarch -mabi=ilp32 -static -nostdlib -nostartfiles \
      -mno-relax -mcmodel=medany -fvisibility=hidden -Wl,--no-warn-rwx-segments \
      -DENTROPY=$entropy -std=gnu99 -O2 \
      -I$src/env/v -I$src/isa/macros/scalar -T $src/env/v/link.ld -o $out/$name.elf \
      $src/env/v/entry.S $src/env/v/*.c "$s"
  fi
  riscv-none-elf-objcopy -O binary $out/$name.elf $out/$name.bin
  riscv-none-elf-nm $out/$name.elf | awk '$3 == "tohost" { print $1 }' > $out/$name.tohost
  n=$((n + 1))
done
echo "$group: $n tests"
