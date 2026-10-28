/* riscv-tests' util.h replacement for the practice-hardcaml MCU. */
#ifndef UTIL_H
#define UTIL_H

#include "mcu.h"

/* dhrystone.h reads `mcycle` through this; the MCU has a memory-mapped
   cycle counter instead of CSRs. */
#define read_csr(reg) ((long)CYCLE)

void setStats(int enable);

#endif
