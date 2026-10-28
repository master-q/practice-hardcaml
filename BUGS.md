# Defect ledger

This file is the experiment's data. Every defect found in this repository is
recorded here, whichever stage found it -- including S0/S1 failures that
were fixed before anything was committed -- so that at the end we
can answer: how many defects did the cheap HardCaml stages catch, and what
kinds of defect only the expensive stages could find?

Testbench, toolchain and golden-model defects are recorded too, in their own
category, because they cost iterations just the same.

## Stages

| Stage | Tool | Typical cost |
|-------|------|--------------|
| S0 | OCaml type check and HardCaml elaboration (width mismatch, combinational loop, undriven wire) | seconds |
| S1 | Cyclesim expect tests, OCaml golden model (`make test`) | seconds |
| S2 | Same benches on Verilator (`make verilate`) | tens of seconds |
| S3 | Yosys + nextpnr: resources, timing, naming (`make synth names`) | seconds |
| S4 | iCEstick hardware (`make -C <project> prog`) | minutes, manual |

## Fields

- **Found at**: the stage where the defect was first observed. OCaml
  syntax errors and API misuse are not defects; elaboration errors that
  describe wrong hardware (a width mismatch, a combinational loop) are S0.
- **Catchable at**: the cheapest stage that can reproduce it, after the
  regression test was added. If this is S4, explain why no cheaper stage can.
- **Class**: one of `logic` (wrong function), `timing` (handshake or
  off-by-one cycle), `reset/init`, `x-propagation`, `clocking`, `io/pinout`,
  `resource` (does not fit), `fmax`, `inference` (BRAM/DSP not inferred as
  intended), `naming`, `testbench`, `model`, `toolchain`.
- **Regression**: the test that now catches it.

## Summary

| Found at | Count |
|----------|-------|
| S0 | 0 |
| S1 | 6 |
| S2 | 0 |
| S3 | 6 |
| S4 | 0 |

By class: testbench 6, toolchain 4, model 1, inference 1, resource 1.
No functional defect in the hardware itself has been found yet: the rv32e
core and the MCU passed lockstep on their first run.

## Entries

### B-0013: MCU expect tests depended on the cross compiler's version

- Date: 2026-10-28
- Project: ip/mcu (test)
- Found at: S1 (maintainer's devcontainer); Catchable at: S1
- Class: testbench
- Symptom: `make` failed locally with different retired-instruction and
  cycle counts (Dhrystone 129582 cycles instead of 128112), while CI and
  the cloud session passed.
- Cause: the expectations contained counts that depend on the code gcc
  generates; the devcontainer image ships a different gcc release than
  Ubuntu 24.04. The hardware behaved identically (same output, lockstep
  clean, same CPI 4.25).
- Fix: expectations hold only hardware-determined facts: program output
  with numbers masked, LEDs, trap, lockstep result, and the Dhrystone CPI.
- Regression: `ip/mcu/test/test_mcu.ml`.

### B-0012: Yosys took 5.5 minutes to read 64 KiB of RAM initial values

- Date: 2026-10-28
- Project: ip/mcu/gen (designs/mcu_i9)
- Found at: S3; Catchable at: S3
- Class: toolchain
- Symptom: the i9 build took 5 min 39 s, of which 5 min 27 s in Yosys.
- Cause: the generator wrote one `ram_bN[i] = 8'hxx;` per byte (65,536
  assignments); Yosys processes them very slowly.
- Fix: one `initial $readmemh(...)` per lane reading the hex file the
  generator already writes. Build time 17.8 s; bitstreams unchanged.
- Regression: none automated (CI time would show it).

### B-0011: benchmark scripts: newline-split list, SIGPIPE under pipefail

- Date: 2026-10-28
- Project: bench/ref_cores
- Found at: S1 (running the scripts); Catchable at: S1
- Class: testbench
- Symptom: area.sh stopped after FemtoRV with no error message;
  dhrystone.sh exited immediately with no output.
- Cause: the Hazard3 source list was built with newlines, and
  `IFS='|' read` only reads the first line, so the read command and top
  name were wrong; `yes | head` fails under `set -o pipefail` because
  `yes` dies of SIGPIPE.
- Fix: space-separated list; `yes ... || true`.
- Regression: none.

### B-0010: reference testbench could not reach the I/O registers on FemtoRV

- Date: 2026-10-28
- Project: bench/ref_cores (tb_femtorv.v)
- Found at: S1 (iverilog); Catchable at: S1
- Class: testbench
- Symptom: FemtoRV32 Quark ran until the testbench timeout and printed
  nothing.
- Cause: FemtoRV32's ADDR_WIDTH defaults to 24, so stores to the UART at
  0x1000_0000 (bit 28) were truncated to address 0 and overwrote the
  program. riscv-ice40's memory map fits in 24 bits; ours does not.
- Fix: the Dhrystone testbench instantiates it with ADDR_WIDTH=32 (area
  figures keep riscv-ice40's configuration).
- Regression: `make -C bench/ref_cores dhrystone`.

### B-0009: cycle/instret counters pushed the iCEstick MCU over its LC budget

- Date: 2026-10-28
- Project: ip/mcu, designs/mcu
- Found at: S3 (MAX_LC); Catchable at: S3
- Class: resource
- Symptom: `make` failed with 1195 LCs against a budget of 1130 after the
  MCU gained two 32-bit memory-mapped counters for Dhrystone.
- Cause: 64 flip-flops, two 32-bit incrementers and a wider I/O mux,
  about 100 LCs on a 1280-LC part.
- Fix: `Config.counters`, off for the iCEstick, on for the i9 (1093 LCs).
- Regression: the MAX_LC budget itself.

### B-0008: naming check ignored leading whitespace under mawk

- Date: 2026-10-28
- Project: scripts/check_names.sh
- Found at: S3 (the check's own negative test); Catchable at: S3
- Class: toolchain (our own check)
- Symptom: a test file with an anonymous flip-flop passed the check.
- Cause: the awk program used `\s`, which mawk (Ubuntu's default awk) does
  not support, so indented names never matched `^_[0-9]+$`.
- Fix: use `[ \t]`.
- Regression: `scripts/selftest.sh` (run by `make`).

### B-0007: naming check counted combinational case muxes as flip-flops

- Date: 2026-10-28
- Project: scripts/check_names.sh, designs/mcu
- Found at: S3; Catchable at: S3
- Class: toolchain (our own check)
- Symptom: 11 "anonymous flip-flops" in the MCU, 6 of them not registers.
- Cause: HardCaml emits `case` multiplexers as `always @*` blocks with
  non-blocking `<=`; the check treated every `<=` target as a flip-flop.
  The other 5 were real: the RAM lanes' read-data registers (now named
  `ram_bN_q`).
- Fix: only targets inside `always @(posedge ...)` count.
- Regression: `scripts/selftest.sh` (run by `make`).

### B-0006: MCU testbench typed ahead and overran the one-byte RX buffer

- Date: 2026-10-28
- Project: designs/mcu (bench)
- Found at: S1; Catchable at: S1
- Class: testbench
- Symptom: the first character of every line was missing from the echo
  ("> ello"), while lockstep with the model stayed clean.
- Cause: the simulated typist sent the next key after *any* output, so it
  typed before the banner and during the banner; the second byte
  overwrote the first in the MCU's one-byte receive buffer. The hardware
  behaves as designed, but a real fast typist would lose characters the
  same way.
- Fix: the typist waits for the echo of each key (and for the "> " prompt
  after Enter). The one-byte buffer is documented in `sw/common/mcu.h`.
- Regression: `designs/mcu/test/test_mcu.ml`.

### B-0005: decoder test read outputs without completing a cycle

- Date: 2026-10-28
- Project: ip/rv32e (test)
- Found at: S1; Catchable at: S1
- Class: testbench
- Symptom: every instruction word "mismatched" with all decoder outputs 0.
- Cause: the test called `cycle_check` and `cycle_before_clock_edge` but
  read the default (after-edge) outputs, which were never updated.
- Fix: use `Cyclesim.cycle` for the purely combinational decoder.
- Regression: `ip/rv32e/test/test_decode.ml`.

### B-0004: Yosys added read/write collision logic around every BRAM

- Date: 2026-10-28
- Project: ip/rv32e, designs/mcu (experiment before writing them)
- Found at: S3; Catchable at: S3
- Class: inference
- Symptom: a 1024 x 8 RAM and a 16 x 32 RAM mapped to 4 SB_RAM40_4K but
  also cost 98 flip-flops and 51 LUTs; hand-written canonical Verilog did
  the same.
- Cause: Yosys 0.33 preserves defined read-during-write behaviour, which
  the iCE40 BRAM does not provide, by adding bypass logic.
- Fix: the `no_rw_check` attribute on every RAM (HardCaml
  `~attributes:[Rtl_attribute.create "no_rw_check"]`), and designs that
  never use read data from a same-cycle write. Result: 0 flip-flops, 1 LUT.
- Regression: `scripts/check_resources.sh` checks the BRAM count; the LC
  count is reported. (A per-design LC ceiling would catch this exact
  regression; not added yet.)

### B-0003: anonymous combinational `reg` misread as a flip-flop

- Date: 2026-10-26
- Project: uart (scripts/check_names.sh)
- Found at: S3 (`make names`); Catchable at: S3
- Class: toolchain (our own check)
- Symptom: the first naming check flagged `reg [7:0] _71` in the hello top.
- Cause: HardCaml emits a multiplexer (the message ROM) as a combinational
  `always` block with a `reg` declaration. The check counted `reg`
  declarations instead of flip-flops.
- Fix: the check now looks at targets of non-blocking assignments; the ROM
  output was also named `tx_byte`.
- Regression: none automated; `scripts/check_names.sh` header documents it.

### B-0002: assembler range-checked shift amounts as registers

- Date: 2026-10-26
- Project: rv32_model (asm.ml)
- Found at: S1; Catchable at: S1
- Class: model
- Symptom: `Asm.srai 6 5 4` and `srai 5 6 31` raised "RV32E has no x28/x31".
- Cause: `slli/srli/srai` reused the R-type encoder, which validates the
  rs2 field as an RV32E register, but that field holds the shift amount.
- Fix: dedicated `shift_imm` encoder.
- Regression: `rv32_model/test/test_machine.ml` "arithmetic ..." and
  "assembler round-trips ..." tests.

### B-0001: testbench sampled `ready` one cycle late

- Date: 2026-10-26
- Project: uart
- Found at: S1; Catchable at: S1
- Class: testbench
- Symptom: sending "OK\n" decoded as "O\n".
- Cause: the bench read outputs with `Cyclesim.outputs ~clock_edge:Before`,
  i.e. the values from before the last clock edge, so it saw the
  transmitter still idle and pushed "K" in the cycle the transmitter had
  already started on "O"; the byte was dropped.
- Fix: read outputs after the edge (the default).
- Regression: `uart/test/test_uart.ml` "uart_tx sends queued bytes back to back".

## Template

    ### B-NNNN: <one-line title>

    - Date:
    - Project:
    - Found at: S?; Catchable at: S?
    - Class:
    - Symptom:
    - Cause:
    - Fix:
    - Regression:
