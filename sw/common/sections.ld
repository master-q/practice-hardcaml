/* Sections for the MCU: code, data and stack all in RAM at 0. Included by
   link_<size>k.ld, which defines the RAM memory region. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  .text : { *(.text.start) *(.text .text.*) } > RAM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > RAM
  .data : { *(.data .data.* .sdata .sdata.*) } > RAM
  .bss (NOLOAD) : ALIGN(4)
  {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > RAM
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
