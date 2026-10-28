# History

A dated log of the project, newest entry first. Each entry records what was
done, what was learned, and the numbers measured that day.

## 2026-10-28: RV32E MCU running C over UART (simulation and synthesis)

- Layout: reusable blocks in `ip/`, board top levels in `designs/`, golden
  models in `models/`, firmware in `sw/` (OpenTitan-style ip/top split).
- ip/uart: added a receiver (two-flop synchronizer, mid-bit sampling), a
  serial-line driver and an incremental monitor for benches, and an ASCII
  waveform test. hardcaml_waveterm only draws Unicode boxes, so
  `testlib/ascii_wave.ml` maps them to `-|+`.
- ip/rv32e: multi-cycle RV32E core (4 cycles per instruction, loads 5,
  shifts 5 + shamt; serial shifter instead of a barrel shifter to save
  area). ALU (one shared 33-bit adder for ADD/SUB/SLT/SLTU/branches) and
  immediate generator (per-bit-range muxes) are proved equal to plain
  references with Hardcaml_verify.Sec + z3; a mutant proves the check can
  fail. The decoder matches the golden model on 362,148 words. The core
  matches the model in lockstep on directed programs, every trap, and 300
  random 80-instruction programs (all passed on the first run).
- models/rv32_model: memory-mapped I/O hooks. In lockstep, I/O loads take
  the value the hardware read, because UART status depends on timing.
- designs/mcu: core + 4 KiB RAM (four 1024 x 8 byte lanes) + UART + LEDs.
  sw/echo (C, riscv64-unknown-elf-gcc -march=rv32e -mabi=ilp32e, 431
  bytes) runs in Cyclesim and on Verilator: banner, echo, upper-cased line,
  line length on the LEDs; 46,208 instructions in lockstep, no mismatch.
- iCE40HX1K: 1079/1280 LCs (84%), 10/16 BRAMs, 46 MHz (12 MHz needed).
- S3 additions: `check_resources.sh` (exact BRAM count per design);
  `check_names.sh` now only counts clocked flip-flops.
- Costs: all S0/S1 tests ~5 s; MCU on Verilator ~11 s; MCU synthesis ~16 s.
- Defects: B-0004..B-0008. The cheap stages found everything so far, but
  all hardware-relevant defects were in testbenches and checks, not in the
  RTL; nothing has been on a board yet.
- Later the same day: `make mcu`, `make mcu-prog`, `make mcu-term` at the
  top level; per-design logic-cell budgets (MAX_LC; mcu 1130, blink 50,
  hello 150) enforced by check_resources.sh, with self-tests.
- icebram flow for the MCU: synthesise once with pseudo-random placeholder
  RAM contents, then swap the firmware into the bitstream per byte lane.
  Firmware-only rebuild: 16.5 s -> 0.33 s. The swapped bitstream is
  byte-identical to direct synthesis (checked by `make icebram-check`).
  Learned: swapping back is impossible because firmware has runs of
  zeros that icebram cannot locate, so the per-build check compares the
  bitstream minus `.ram_data` instead.
- Policy: GitHub text (issues, comments, PRs) must be English ASCII,
  enforced by Claude Code and Codex PreToolUse hooks modelled on takibi.
- Tools added: z3 (SAT for Hardcaml_verify), hardcaml_verify,
  gcc-riscv64-unknown-elf.

## 2026-10-26: toolchain, test ladder, UART, RV32E model

- Verified that the devcontainer toolchain also works in a Claude Code cloud
  session (Ubuntu 24.04): yosys, nextpnr-ice40, icestorm from apt; OCaml
  5.3.0 and hardcaml v0.17.1 from opam. Cloud sessions do not use the
  devcontainer, so `.claude/hooks/session-start.sh` now installs the same
  tools. The network policy had to allow `opam.ocaml.org`; with that, all
  sources came from the opam cache even while `codeload.github.com` was
  still blocked.
- Built the test ladder (docs/WORKFLOW.md): S1 Cyclesim expect tests, S2 the
  same bench on Verilator via hardcaml_verilator, S3 Yosys + nextpnr with a
  flip-flop naming check, S4 the board (`make prog`, by hand).
- blink: split into library / generator / test; uses `Hierarchy` and a
  named counter. 29 LCs, ~179 MHz.
- uart: 8N1 transmitter (Always state machine) and a "Hello, iCEstick!"
  top level with a power-on reset (the board has no reset button). Software
  UART decoder in the bench, so the same expected bytes apply to Cyclesim,
  Verilator and a terminal capture from the board. 113 LCs, ~143-160 MHz
  (varies with placement seed), 0 anonymous flip-flops.
- Stage cost: `dune test` for all projects ~2 s incremental; the Verilator
  stage for uart ~21 s (two C++ model builds).
- rv32_model: RV32E decoder, executor with a per-instruction retirement
  record (for future lockstep comparison with the core), traps, and a small
  assembler so tests need no RISC-V toolchain.
- Defects found: three, all at S1 or S3 (BUGS.md B-0001..B-0003).
- Toolchain findings:
  - HardCaml v0.17 API differs from older examples: `select s hi lo` is
    positional; wires use `<==`.
  - hardcaml_verilator v0.17.0 hard-codes `--no-threads` for Verilator 4,
    which Verilator 5 rejects; set `verilator_version = V5`. In quiet mode
    it runs `cmd &>file` through /bin/sh; dash parses that as a background
    job, so the build races the link and fails with "Could not find
    verilator shared library". Workaround: `verbose = true`.
- Policy: English/ASCII-only repository, enforced by `.githooks/` and CI
  (modelled on takibi-lang/takibi).
- Policy: defects caught at every stage, including S0 (elaboration) and S1
  failures fixed before committing, are recorded in BUGS.md.
- Policy: agents push directly to `main`; no branches or pull requests.
- Decision on a UART bootloader: not now. It would cost LCs on a 1280-LC
  part. Program images will instead be swapped into the BRAM initial values
  of an already placed-and-routed bitstream with `icebram`, which takes
  seconds and costs no logic (docs/WORKFLOW.md).
