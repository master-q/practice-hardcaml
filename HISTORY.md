# History

A dated log of the project, newest entry first. Each entry records what was
done, what was learned, and the numbers measured that day.

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
- Decision on a UART bootloader: not now. It would cost LCs on a 1280-LC
  part. Program images will instead be swapped into the BRAM initial values
  of an already placed-and-routed bitstream with `icebram`, which takes
  seconds and costs no logic (docs/WORKFLOW.md).
