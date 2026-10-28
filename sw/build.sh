#!/usr/bin/env bash
# Build one firmware image for the MCU (called by sw/dune).
#
#   build.sh OUT.bin ARCH RAM_KIB [CFLAGS...] -- SOURCES...
#
# ARCH is rv32e or rv32i; RAM_KIB selects common/link_<RAM_KIB>k.ld.
set -euo pipefail
out=$1 arch=$2 ram=$3
shift 3
cflags=()
while [ "$1" != "--" ]; do cflags+=("$1"); shift; done
shift
case $arch in
  rv32e) march=rv32e mabi=ilp32e ;;
  rv32i) march=rv32i mabi=ilp32 ;;
  *) echo "unknown arch $arch" >&2; exit 2 ;;
esac
elf=${out%.bin}.elf
riscv-none-elf-gcc -march=$march -mabi=$mabi -Os -ffreestanding -nostdlib \
  -mno-relax -Wl,--no-warn-rwx-segments -Icommon -Ilibc/include \
  -Lcommon -T common/link_${ram}k.ld "${cflags[@]}" -o "$elf" common/crt0.S "$@" -lgcc
riscv-none-elf-objcopy -O binary "$elf" "$out"
