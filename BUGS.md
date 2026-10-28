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
| S2n | Post-synthesis: the Yosys iCE40 netlist read back into HardCaml, S1 MCU bench in lockstep and the board top at pin level (`make netlist-sim`) | tens of seconds |
| S3 | Yosys + nextpnr: resources, timing, naming (`make synth names`) | seconds |
| S4 | iCEstick hardware (`make -C <project> prog`) | minutes, manual |

## Analysis (audit of B-0001..B-0016, 2026-10-28)

Root-cause categories, independent of the stage that found them:

| Category | Defects | Notes |
|----------|---------|-------|
| Implicit assumption about silicon or tools, not written in the source | B-0004, B-0012, B-0014 | collision semantics of BRAM, Yosys cost of init style, power-up state and BRAM readiness |
| Environment drift (different tool releases) | B-0013, B-0015 | gcc and Yosys/nextpnr differ between devcontainer and CI |
| Testbench timing or protocol | B-0001, B-0005, B-0006, B-0010, B-0016 | the benches are as error-prone as the RTL |
| Our own checks and scripts | B-0003, B-0007, B-0008, B-0011 | each check now has a negative test |
| Golden model / assembler | B-0002 | |
| Area | B-0009 | caught by the LC budget |
| RTL function | none so far | the core, MCU and UART passed lockstep on their first run |

Findings for the project's question:
- Every RTL-level functional property was settled by the cheap stages;
  no functional RTL defect has reached S2 or S4.
- The only defect seen first on hardware (B-0014) is about start-up: the
  core read block RAM 1.25 us after configuration (confirmed by
  ablation). No simulation stage can see it: Cyclesim, Verilator and the
  four-state board simulation all model a chip that is ready at time 0.
  It is the first data point of an S4-only class, and it is not an RTL
  logic error but an assumption about the silicon. The four-state board
  simulation (`make board-sim`) still closes the neighbouring gap
  (uninitialised memories, registers without reset), which two-state
  Cyclesim hides by starting everything at 0.
- Results that depend on the toolchain (instruction counts, LC counts)
  must not be compared across environments; record versions.

Prevention now in place: `make board-sim` in every `make`; explicit
initial contents for memories whose contents matter; reset hold after
configuration; flashing gated on all S3 checks; tool versions recorded;
one change per board experiment, or an ablation switch (AGENTS.md).

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
| S2 | 1 (board-sim) |
| S3 | 6 |
| S4 | 2 |

By class: testbench 7, toolchain 4, model 1, inference 1, resource 1,
reset/init 1, process/environment 1.
No functional defect in the hardware itself has been found yet: the rv32e
core and the MCU passed lockstep on their first run.

## Entries

### B-0021: interrupt test firmware broke the MCU bench's typing protocol

- Date: 2026-10-29
- Project: sw/irq (new firmware)
- Found at: S1; Catchable at: S1
- Class: testbench timing or protocol
- Symptom: the i9 interrupt test printed its self-test line and echoed
  only the first key ("> I"); the bench never typed the rest.
- Cause: the MCU bench types the next key only after the previous one is
  echoed unchanged (B-0006); the new firmware echoed keys upper-cased.
- Fix: echo as typed and print the upper-cased line on Enter, as sw/echo.
- Regression: the i9 interrupt test in ip/mcu/test/test_mcu.ml.

### B-0020: core harness sampled the Fetch flag one cycle late

- Date: 2026-10-29
- Project: ip/rv32/bench (core harness, Zicsr)
- Found at: S1; Catchable at: S1
- Class: testbench timing or protocol
- Symptom: the new missed-interrupt/priority check reported "core took
  interrupt N, expected none" for every interrupt.
- Cause: the harness read the core's `fetch` output before
  `Cyclesim.cycle_before_clock_edge`, i.e. the previous cycle's value, so
  it recorded the irq input of the wrong cycle (same family as B-0001).
- Fix: read it after the combinational update.
- Regression: the directed interrupt tests and the checker's negative
  tests (`lockstep catches interrupt mistakes`) in ip/rv32/test/test_zicsr.ml.

### B-0019: mcycle/minstret undriven in the core without Zicsr

- Date: 2026-10-29
- Project: ip/rv32 (core)
- Found at: S0 (HardCaml elaboration, "circuit input signal must have a
  port name (unassigned wire?)"); Catchable at: S0
- Class: RTL structure (undriven register)
- Symptom: every non-Zicsr build failed to elaborate after the counters
  were added.
- Cause: the counter registers were assigned only in the Zicsr branch of
  the Always block; an Always register that is never assigned has an
  undriven input.
- Fix: assign them 0 without Zicsr (removed by synthesis).
- Regression: every existing S1 test elaborates the non-Zicsr core.

### B-0018: netlist reader rejected Yosys 0.70's $scopeinfo cells

- Date: 2026-10-29
- Project: testlib/netlist
- Found at: S2n; Catchable at: S2n
- Class: our own checks (assumption about a tool's output)
- Symptom: after moving to the pinned OSS CAD Suite (Yosys 0.70), the
  board-level netlist simulation stopped with "Unsupported cell
  $scopeinfo". The MCU-level run, from a flattened HardCaml circuit, was
  not affected.
- Cause: newer Yosys keeps the flattened module hierarchy as `$scopeinfo`
  cells; Yosys 0.33 did not emit them. The reader rejects every unknown
  cell on purpose, so it failed loudly instead of mis-simulating.
- Fix: skip `$scopeinfo` (no logic).
- Regression: `make netlist-sim` runs the hierarchical board top on the
  pinned Yosys.

### B-0017: start-up hold was half the documented length

- Date: 2026-10-29
- Project: ip/mcu (Mcu.Startup), designs/mcu, designs/mcu_i9
- Found at: S2n (by eye); Catchable at: S1
- Class: specification / off-by-one (counter width)
- Symptom: the new board-level netlist simulation printed the prompt at
  12.5 ms, while Mcu.Startup, AGENTS.md and the iCEstick top promise a
  hold of at least 20 ms (about 22 ms). The RTL board-sim log showed the
  same time; nobody had compared it with the documentation.
- Cause: the hold ends when the counter's msb rises, after 2^(width-1)
  cycles, but the width was chosen as ceil_log2(cycles) so the hold was
  2^17 cycles = 10.9 ms at 12 MHz (10.5 ms on the i9). This dates from
  80f33cd (18-bit counter "2^18 cycles, about 22 ms"). B-0014 was fixed on
  the board with this 10.9 ms hold, so the shorter hold is known to work.
- Fix: width = ceil_log2(cycles) + 1: 21.8 ms at 12 MHz, 21.0 ms at
  25 MHz. The i9 testbench's start value for boot_count follows the new
  width (it skips most of the hold). The longer hold is strictly more
  conservative and has not been flashed yet.
- Regression: ip/mcu/test/test_startup.ml (S1) measures the hold at
  three clock rates against min_hold_ms; it failed before the fix
  (1025 cycles for a minimum of 2000).

### B-0016: board-sim testbench: Verilog has no \r string escape

- Date: 2026-10-28
- Project: designs/mcu (tb_top.v)
- Found at: S2 board-sim; Catchable at: S2 board-sim
- Class: testbench
- Symptom: the board simulation printed the right text but reported FAIL.
- Cause: the expected tail was written as the string "\r\nHI\r\n> ";
  Verilog string literals support \n but not \r, so it never matched (and
  the first version also compared 12 bytes against an 8-byte string).
- Fix: compare against 64'h0d0a48490d0a3e20.
- Regression: `make board-sim` (its PASS line is required by make).

### B-0015: flashing bypassed the S3 checks; LC counts differ between toolchains

- Date: 2026-10-28
- Project: mk/icestick.mk, mk/ecp5.mk
- Found at: S4 (maintainer's build log); Catchable at: S3
- Class: process / environment
- Symptom: the maintainer's `make mcu-prog` reported 1139 LCs, over the
  1130 budget, and flashed anyway. The same sources give 1119 LCs with
  the cloud/CI toolchain.
- Cause: `prog` depended only on the bitstream, not on `resources` and
  `names`; and the devcontainer's Yosys/nextpnr differ from Ubuntu
  24.04's (as its gcc does, B-0013).
- Fix: `prog` and `flash` depend on `all names`; every build writes
  `build/versions.txt` (`scripts/versions.sh`), CI prints the versions;
  the iCEstick budget is 1160 to cover the observed spread.
- Regression: the Makefile dependency.

### B-0014: no UART output from the MCU on the iCEstick

- Date: 2026-10-28
- Project: designs/mcu
- Found at: S4 (maintainer, first board test)
- Status: fixed by commit 80f33cd (board confirmed: banner, echo, upper
  case). Root cause decided by ablation on the board (2026-10-28):
  - EXPERIMENT=no-hold (register file initialised, no reset hold): no
    output -- the defect reproduces.
  - EXPERIMENT=no-regfile-init (reset hold, no explicit initialisation):
    works.
  So the cause is (A): the core started fetching from block RAM about
  1.25 us (15 cycles) after configuration. The most likely mechanism is
  that iCE40 block RAM is not readable that early after configuration;
  the experiment shows only that waiting fixes it, not which part of the
  chip needs the time.
- Symptom: after `make mcu-prog`, `make mcu-term` showed nothing and typed
  keys were not echoed. `designs/hello` (no CPU, no RAM) worked on the
  same board, port and pins.
- What simulation says: the generated Verilog with the firmware in the
  RAM boots and echoes at pin level in Icarus Verilog (`make board-sim`).
- The two changes in 80f33cd and what each predicts:
  - (A) Reset hold of about 22 ms after configuration (before: the core
    fetched from block RAM 15 cycles, 1.25 us, after configuration).
    No simulator models block RAM right after configuration, so if (A)
    is the cause the class is reset/init and it is catchable only at S4.
  - (B) Explicit zero initialisation of the register file (x0 is never
    written and reads as the RAM's initial value). Without it,
    `make board-sim` fails (four-state X), so if (B) is the cause on the
    maintainer's toolchain the class is reset/init, catchable at S2
    board-sim. On the cloud toolchain the register file was already zero
    in the bitstream.
- Ablation (on the board, one flash each):
  `make -C designs/mcu clean && EXPERIMENT=no-hold make mcu-prog` and
  `make -C designs/mcu clean && EXPERIMENT=no-regfile-init make mcu-prog`.
- Found at: S4; Catchable at: S4 only. No simulator models the chip right
  after configuration; `make board-sim` passes with EXPERIMENT=no-hold.
- Class: reset/init (silicon start-up timing).
- Regression: the reset-hold rule in AGENTS.md; `EXPERIMENT=no-hold`
  remains available to re-check on new boards or toolchains. (B) was not
  the cause, but its fix stays because it makes board-sim honest.

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
