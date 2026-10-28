/* Measurement hooks for riscv-tests' Dhrystone on the practice-hardcaml MCU.
   setStats(1) is called just before the timed loop, setStats(0) just after
   it; we record the CYCLE and INSTRET counters and print the difference in
   a fixed format that the testbench parses:

     dhrystone: runs=N cycles=C instret=I

   (debug_printf, used for the verbose output, is defined empty in
   riscv-tests' dhrystone.c.) */
#include "mcu.h"
#include "util.h"
#include "dhrystone.h"

static unsigned int start_cycle, start_instret;

void setStats(int enable)
{
  unsigned int cycle = CYCLE, instret = INSTRET;
  if (enable) {
    start_cycle = cycle;
    start_instret = instret;
  } else {
    printf("dhrystone: runs=%d cycles=%u instret=%u\n",
           NUMBER_OF_RUNS, cycle - start_cycle, instret - start_instret);
  }
}
