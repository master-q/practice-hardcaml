# Dhrystone 2.2 (riscv-tests)

`dhrystone.c`, `dhrystone.h` and `dhrystone_main.c` come from
[riscv-tests](https://github.com/riscv-software-src/riscv-tests)
(`benchmarks/dhrystone`, BSD license, see `LICENSE.riscv-tests`). They are
Weicker's Dhrystone 2.x with a RISC-V timing harness. The only change here:
`NUMBER_OF_RUNS` in `dhrystone.h` can be overridden with `-D`.

`util.h` and `harness.c` are ours: the riscv-tests timing macros read the
MCU's memory-mapped CYCLE counter instead of the `mcycle` CSR (the core has
no CSRs yet, see issue #3), and `setStats` records cycles and retired
instructions around the timed loop and prints them.

The riscv-ice40 survey uses a different harness around the same benchmark
body, so DMIPS/MHz is comparable; absolute run counts and printed text are
not.

DMIPS/MHz = 1e6 / (cycles per run * 1757).
