/* MCU with 4 KiB of RAM. */
MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 4K
}
INCLUDE sections.ld
