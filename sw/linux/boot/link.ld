/* Boot ROM at 0 (Soc_map.boot_rom_base), code only. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)
SECTIONS
{
  . = 0x0;
  .text : { *(.text) }
}
