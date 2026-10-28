/* MCU with 64 KiB of RAM. */
MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}
INCLUDE sections.ld
