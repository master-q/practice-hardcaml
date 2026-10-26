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
- **Generated Verilog is an artifact.** Never edit it; change the HardCaml
  source and regenerate.
- **Name every flip-flop.** Use `let%hw`, `let%hw_var` or `(--)` for every
  register, and build designs with `Hierarchy.In_scope` so module boundaries
  survive into the Verilog. `make names` fails on anonymous flip-flops.
- **Test cheapest first.** Every design module gets a Cyclesim expect test in
  its project's `test/` directory before it goes to the board. Testbenches
  live in a library that takes a `Cyclesim.t`, so the same bench also runs on
  Verilator (see `uart/bench`).
- **Every defect is recorded in `BUGS.md`**, with the cheapest stage that
  could have caught it. A bug first seen on Verilator or the board must get a
  regression test at the cheapest stage that can reproduce it, or an
  explanation of why none can.
- **Keep `HISTORY.md` up to date.** Add a dated entry with the gist of each
  working session: what was done, what was learned, measured numbers.
  Newest entry first. Do not turn `README.md` into a log.

## Layout

| Path | What |
|------|------|
| `blink/` | LED blinker, the smallest end-to-end example |
| `uart/` | 8N1 UART transmitter and a "hello" top level; shared bench + Verilator stage |
| `rv32_model/` | RV32E instruction-set golden model (OCaml) and a tiny assembler |
| `mk/icestick.mk` | Shared HardCaml -> Yosys -> nextpnr -> icepack rules |
| `scripts/` | Policy checks (`check_ascii.sh`, `check_names.sh`) and setup |
| `docs/WORKFLOW.md` | HDL landscape, AI-assisted workflows, and the workflow we adopt |

A board project has `src/` (library), `bin/main.ml` (prints Verilog for
module `top`), `test/` (Cyclesim expect tests), optionally `bench/` and
`verilator/`, an `icestick.pcf`, and a two-line `Makefile` including
`../mk/icestick.mk`. Add new board projects to `BOARD_PROJECTS` in the root
`Makefile` and to the table in `README.md`.

## Commands

    make              # per-commit gate: langcheck, dune test, synth, names
    make ci           # also runs the Verilator stage
    make -C uart      # build uart/build/top.bin
    make -C uart prog # flash it (needs a board on USB)

## Environment

Local: `.devcontainer/devcontainer.json`. Claude Code cloud sessions:
`.claude/hooks/session-start.sh` installs the same tools. Keep the two in
sync whenever a tool or opam package is added.

Toolchain notes:
- HardCaml v0.17: `select s hi lo` takes positional arguments; wires are
  assigned with `<==`; Always variables with `<--`.
- hardcaml_verilator v0.17.0 needs `verilator_version = V5` and
  `verbose = true` (see the comment in `uart/verilator/main.ml`).
