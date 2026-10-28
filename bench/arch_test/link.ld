/* riscv-arch-test image for the rv32 core harness: everything in 2 MiB of
   RAM at address 0, entry point first (jal-01 is about 1.7 MiB,
   the branch tests over 200 KiB). */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)
MEMORY { RAM (rwx) : ORIGIN = 0, LENGTH = 2048K }
SECTIONS
{
  .text.init : { *(.text.init) } > RAM
  .text : { *(.text .text.*) } > RAM
  .data : { *(.data .data.* .sdata .sdata.*) } > RAM
  .bss : { *(.bss .bss.* .sbss .sbss.*) } > RAM
}
