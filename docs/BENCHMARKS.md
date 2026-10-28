# Benchmarks: rv32 vs. the riscv-ice40 survey cores

Measured 2026-10-28. Reproduce with `make -C bench/ref_cores` (needs
network access to fetch the reference cores) and `make test` (our core).

The reference set is the survey in
[MrJake222/riscv-ice40](https://github.com/MrJake222/riscv-ice40) at commit
5f4633a8, using the exact submodule commits it pins
(`bench/ref_cores/fetch.sh`). Its own README reports whole-SoC LUT counts
on the iCE40UP5K and no Dhrystone results, so both tables below were
measured here, under the same conditions for every core.

## Area (core only, Yosys synthesis, no place and route)

Each core alone, configured as in riscv-ice40 (`bench/ref_cores/area.sh`).
No memories or peripherals; the register file is part of each core.

| Core | iCE40 LUT4 | SB_CARRY | FF | SB_RAM40_4K | ECP5 LUT4 | CCU2C | FF | DP16KD | DPR16X4 |
|------|-----------:|---------:|---:|------------:|----------:|------:|---:|-------:|--------:|
| rv32 (this repo, RV32I) | 884 | 94 | 145 | 2 | 1064 | 51 | 177 | 0 | 16 |
| rv32 (this repo, RV32E) | 910 | 94 | 145 | 2 | 1049 | 51 | 177 | 0 | 8 |
| PicoRV32 (ENABLE_COUNTERS=1) | 1678 | 405 | 597 | 4 | 1638 | 211 | 573 | 0 | 32 |
| FemtoRV32 Quark | 883 | 191 | 158 | 4 | 1309 | 103 | 223 | 0 | 32 |
| Hazard3 (riscv-ice40 config) | 3334 | 346 | 572 | 4 | 5286 | 181 | 595 | 0 | 32 |

Notes:
- PicoRV32's counters (64-bit cycle and instret CSRs) account for many of
  its flip-flops; riscv-ice40 enables them for its Dhrystone harness. Our
  core has no CSRs; the MCU's memory-mapped counters are outside the core.
- DarkRISCV is missing: riscv-ice40 builds it with a generation script
  (`darkriscv-build/run.sh`) that is not part of the pinned tree.
- VexRiscv is missing: it is generated from Scala (SpinalHDL).

## Dhrystone (same binary on every core)

`sw/dhrystone_sim.bin`: Dhrystone 2.2 from riscv-tests, 50 runs, built
once with `riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32`
(multiply and divide from libgcc), gcc 13.2.0 as shipped with Ubuntu 24.04
(the cloud sessions and CI). Other gcc releases generate different code:
the devcontainer's gcc retires about 1% more instructions (30,481 instead
of 30,138 in the timed loop) and scores 0.219; the CPI (4.25) is the same.
Compare cores only with the same binary. The binary is identical for every core,
so every core retires the same instructions (about 30,100 in the timed loop);
only the cycle count differs. Our core runs in Cyclesim in lockstep with
the golden model (`ip/mcu/test/test_mcu.ml`); the reference cores run in
Icarus Verilog with a memory of the same latency as our block RAM
(`bench/ref_cores/dhrystone.sh`).

| Core | Memory | Cycles / run | DMIPS/MHz | CPI |
|------|--------|-------------:|----------:|----:|
| FemtoRV32 Quark | 1-cycle read latency | 2040 | 0.279 | 3.39 |
| PicoRV32 | zero wait (best case) | 2464 | 0.231 | 4.09 |
| **rv32 (this repo, RV32I)** | 1-cycle read latency (BRAM) | **2562** | **0.222** | **4.25** |
| PicoRV32 | 1-cycle read latency | 3317 | 0.172 | 5.50 |

DMIPS/MHz = 1e6 / (cycles per run x 1757), rounded here; the firmware
itself prints it truncated to thousandths.

## Reading the results

- rv32 is the smallest core in LUTs on both families (about the size of
  FemtoRV32 Quark on iCE40, 20% smaller on ECP5) and needs no carry chain
  beyond its two adders, at a Dhrystone score between PicoRV32 and
  FemtoRV32.
- Where the cycles go: rv32 spends 4 cycles on every instruction (fetch,
  decode, read rs1, read rs2 + execute) because the register file is a
  block RAM with one read port, and shifts are serial (1 cycle per bit).
  FemtoRV32 reads both registers from LUT/FF storage in parallel and uses
  a 2-cycle decode/execute path for most instructions. A second register
  file read port (duplicated BRAM) or overlapping fetch with execute would
  close most of the gap; see the pipeline issue.
- On the Colorlight i9 at 25 MHz, rv32 gives 0.222 x 25 = 5.6 DMIPS.

## Full designs (place and route)

| Design | Device | Logic | FF | Block RAM | Fmax (needed) |
|--------|--------|------:|---:|----------:|--------------:|
| designs/mcu (RV32E, 4 KiB) | iCE40HX1K | 1059-1093 LC | | 10 / 16 | 45 MHz (12) |
| designs/mcu_i9 (RV32I, 64 KiB) | ECP5 LFE5U-45F | 1491 / 43848 LUT slots | 340 | 32 / 108 DP16KD | 57 MHz (25) |
