# practice-hardcaml: agent and contributor guide

This is the canonical guidance file for every coding agent (Claude Code,
Codex, ...) and human contributor. `CLAUDE.md` only points here.

## Goal

Build a small RV32E CPU entirely in HardCaml and run it on an iCEstick
(Lattice iCE40HX1K-TQ144, 12 MHz, 1280 LCs, 8 KB BRAM) through the open
Yosys / nextpnr / icestorm flow.

The real research question: can cheap HardCaml-level verification (Cyclesim,
expect tests, an OCaml golden model) catch most hardware defects before the
expensive stages (Verilator, synthesis, the board)? `BUGS.md` collects the
evidence; `docs/WORKFLOW.md` describes the method.

## Always-on rules

- **English and ASCII only.** Every file, file name, commit message, code
  comment and document in this repository is written in English using ASCII
  characters only, even when the maintainer talks to you in another
  language. Enforced by `make langcheck`, the git hooks in `.githooks/`
  (enabled by `make setup`) and CI. Do not bypass them with `--no-verify`.
  Write "->" not arrows, "--" not dashes, plain quotes not curly ones.
- **GitHub text is English ASCII too.** Issue titles and bodies, comments,
  pull requests and reviews are written in English using ASCII only, even
  when the maintainer writes to you in Japanese; translate the request.
  Agent hooks enforce this (`scripts/hooks/github-text-ascii-policy.sh`,
  wired into `.claude/settings.json` and `.codex/hooks.json`). Agents
  without hooks (e.g. opencode) must follow this rule by hand.
- **Generated Verilog is an artifact.** Never edit it; change the HardCaml
  source and regenerate.
- **Name every flip-flop.** Use `let%hw`, `let%hw_var` or `(--)` for every
  register, and build designs with `Hierarchy.In_scope` so module boundaries
  survive into the Verilog. `make names` fails on anonymous flip-flops.
- **Test cheapest first.** Every design module gets a Cyclesim expect test in
  its project's `test/` directory before it goes to the board. Testbenches
  live in a library that takes a `Cyclesim.t`, so the same bench also runs on
  Verilator (see `designs/mcu/bench`).
- **Prove what can be proved.** When a block has an area-optimised
  implementation, keep a straightforward `reference` next to it and prove
  them equivalent with `Hardcaml_verify.Sec` (see `ip/rv32e/test/test_formal.ml`).
  Every checker (formal, lockstep, naming) also gets a negative test showing
  it can fail.
- **Memories must land in block RAM.** Build RAMs with `Ram.create`
  (registered read port) and the `no_rw_check` attribute, never read and
  write the same RAM in the same cycle when the read data is used, and set
  `EXPECT_BRAM` in the project Makefile; `make` fails if nextpnr places a
  different number of SB_RAM40_4K blocks.
- **Every defect is recorded in `BUGS.md`, at every stage, S0 and S1
  included.** This covers failures you hit and fix yourself while developing,
  before anything is committed: a failing expect test, a width error from
  HardCaml elaboration, a golden-model mismatch. Cheap-stage catches are the
  experiment's main data; leaving them out makes the cheap stages look
  useless. Not recorded: OCaml syntax errors and API misuse (wrong function
  name or argument labels); count those only in `HISTORY.md` if notable.
  A defect first seen at S2 or later must get a regression test at the
  cheapest stage that can reproduce it, or an explanation of why none can.
- **Push directly to `main`** (maintainer, 2026-10-26). No feature branch
  or pull request is needed; run `make` (or `make ci`) before pushing so
  `main` stays green.
- **Keep `HISTORY.md` up to date.** Add a dated entry with the gist of each
  working session: what was done, what was learned, measured numbers.
  Newest entry first. Do not turn `README.md` into a log.

## Layout

Follows the usual HDL split between reusable IP and chip/board top levels
(as in OpenTitan's `hw/ip` and `hw/top_*`).

| Path | What |
|------|------|
| `ip/uart/` | 8N1 UART transmitter and receiver; bench with line driver and monitors |
| `ip/rv32/` | RV32I/RV32E core: ALU, immediate generator, decoder, multi-cycle core; lockstep bench |
| `ip/mcu/` | The MCU (core + RAM + UART + LEDs + counters) with a `Config.t`; `gen/` holds the board generators' shared code |
| `designs/blink/` | LED blinker, the smallest end-to-end example |
| `designs/hello/` | Prints "Hello, iCEstick!" over the UART |
| `designs/mcu/` | iCEstick top for the MCU (RV32E, 4 KiB) |
| `designs/mcu_i9/` | Colorlight i9 (ECP5 LFE5U-45F) top for the MCU (RV32I, 64 KiB); `mk/ecp5.mk` flow |
| `bench/ref_cores/` | Reference cores (riscv-ice40 survey): area and Dhrystone, see docs/BENCHMARKS.md |
| `models/rv32_model/` | RV32I/RV32E golden model (OCaml), MMIO hooks, tiny assembler |
| `sw/` | Firmware (crt0, linker scripts, `mcu.h`, minimal libc, echo, Dhrystone) |
| `testlib/` | Test helpers: ASCII waveforms, shared Verilator config |
| `mk/icestick.mk`, `mk/ecp5.mk` | Shared board flows (iCE40: icepack/icebram; ECP5: ecppack/ecpbram) |
| `scripts/` | Policy and S3 checks (`check_ascii.sh`, `check_names.sh`, `check_resources.sh`) |
| `docs/WORKFLOW.md` | HDL landscape, AI-assisted workflows, and the workflow we adopt |

An IP block (`ip/<name>/`) has `src/` (library), `test/` (S0/S1 tests) and
usually `bench/` (testbenches taking a `Cyclesim.t`). A board design
(`designs/<name>/`) adds `bin/main.ml` (prints Verilog for module `top`),
optionally `verilator/` (S2), an `icestick.pcf`, and a short `Makefile`
setting `PROJECT`, `EXPECT_BRAM`, `MAX_LC` and optionally `FIRMWARE` before including
`../../mk/icestick.mk`. Add new designs to `BOARD_PROJECTS` in the root
`Makefile` and to the table in `README.md`.

## Commands

    make                     # per-commit gate: langcheck, S0/S1, synth + S3 checks
    make ci                  # also runs the Verilator stage (S2)
    make -C designs/mcu      # build designs/mcu/build/top.bin with sw/echo.bin inside
    make mcu-prog            # flash it (needs a board on USB)
    make mcu-term            # talk to it at 115200 baud

Firmware-only changes do not re-synthesise: the MCU bitstream is built
with placeholder RAM contents and `icebram` swaps the firmware in
(docs/WORKFLOW.md, "Program loading").

## Environment

Local: `.devcontainer/devcontainer.json`. Claude Code cloud sessions:
`.claude/hooks/session-start.sh` installs the same tools. Keep the two in
sync whenever a tool or opam package is added.

Toolchain notes:
- HardCaml v0.17: `select s hi lo` takes positional arguments; wires are
  assigned with `<==`; Always variables with `<--`.
- HardCaml v0.17: `repeat s n`, `srl s n` are positional; memories have no
  initial contents (the mcu generator inserts `initial` blocks).
- hardcaml_verilator v0.17.0 needs `verilator_version = V5` and
  `verbose = true`; use `Testlib.Verilator_config.config`.
- hardcaml_waveterm draws Unicode boxes; print waveforms with
  `Testlib.Ascii_wave.print` to stay ASCII.
- `Hardcaml_verify.Sec` calls the `z3` binary.
- Firmware: `riscv64-unknown-elf-gcc` with `-march=rv32e -mabi=ilp32e` (iCEstick)
  or `-march=rv32i -mabi=ilp32` (i9), see `sw/build.sh` and `sw/dune`.
- Memory initial contents: emit `$readmemh` (ip/mcu/gen), never one
  assignment per word: Yosys took 5.5 minutes for 64 KiB that way.
