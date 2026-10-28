# History

A dated log of the project, newest entry first. Each entry records what was
done, what was learned, and the numbers measured that day.

## 2026-10-28 (later): RV32I, Colorlight i9 port, Dhrystone and comparison

Direction (maintainer): target the Colorlight i9 v7.2 (ECP5 LFE5U-45F)
instead of pico-ice; first RV32I plus a Dhrystone and area comparison with
the riscv-ice40 survey cores; pipeline, M, MMU, caches/SDRAM, Ethernet MAC
and dual core are deferred to issues.

- RV32I: the golden model, decoder and core take `base` (Rv32i | Rv32e).
  The decoder matches the model on 362k words for both; random lockstep
  passes for both (31k and 41k instructions). The register file grows
  from 16 to 32 entries at no block-RAM cost.
- ip/rv32e renamed ip/rv32; the MCU moved to ip/mcu with a Config
  (base, RAM size, baud divider, optional counters); designs/mcu and the
  new designs/mcu_i9 are thin board tops sharing ip/mcu/gen.
- Firmware: minimal libc (printf, string functions), linker scripts per
  RAM size, sw/build.sh; Dhrystone 2.2 from riscv-tests (BSD) with a
  harness reading memory-mapped CYCLE/INSTRET.
- Dhrystone runs in Cyclesim in lockstep with the model (48k instructions,
  no mismatch): 2562 cycles/run, CPI 4.25, 0.222 DMIPS/MHz.
- Colorlight i9 flow (mk/ecp5.mk): synth_ecp5, nextpnr-ecp5, ecpbram swap
  (bit-identical to direct synthesis), ecppack, openFPGALoader. 1491/43848
  LUT slots, 340 FFs, 32 DP16KD (64 KiB), 57 MHz against 25 MHz. Pins from
  wuxx/Colorlight-FPGA-Projects (clock P3, UART J17/H18 via the ext
  board's DAPLink, LED L2); not yet tried on hardware.
- Reference comparison (docs/BENCHMARKS.md): same Dhrystone binary on
  PicoRV32 and FemtoRV32 Quark in iverilog; core-only area for those and
  Hazard3. rv32 is the smallest core in LUTs; its Dhrystone score (0.222)
  sits between PicoRV32 with 1-cycle memory (0.172) / zero-wait memory
  (0.231) and FemtoRV32 Quark (0.279). The 4-cycle minimum per
  instruction (single-port register file in block RAM) is the main cost.
- Build-time finding: per-byte `initial` assignments for 64 KiB took Yosys
  5.5 minutes; `$readmemh` takes seconds (B-0012).
- Defects: B-0009..B-0012 (one resource, caught by the LC budget; the rest
  in scripts and testbenches). Again no functional RTL defect.

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
