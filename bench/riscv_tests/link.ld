/* riscv-tests at 0x8000_0000 (their DRAM_BASE, and the Linux SoC's RAM;
   the virtual-memory tests depend on it); tohost on its own page as in
   env/p/link.ld. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
