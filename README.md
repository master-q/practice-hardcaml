# practice-hardcaml

A CPU written in [HardCaml](https://github.com/janestreet/hardcaml), running
on the [iCEstick](https://www.latticesemi.com/en/Products/DevelopmentBoardsAndKits/iCEstick)
(iCE40HX1K-TQ144, 12 MHz) through the open-source Yosys / nextpnr / icestorm
flow.

The underlying question is whether cheap verification in HardCaml can catch
most hardware defects before simulation of the generated Verilog and testing
on the board. See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the method,
[BUGS.md](BUGS.md) for the evidence, and [HISTORY.md](HISTORY.md) for the
project log.

## Projects

| Directory | Description | Status |
|-----------|-------------|--------|
| [blink](blink/) | LED blinker | Cyclesim + synth |
| [uart](uart/) | 8N1 UART TX, prints "Hello, iCEstick!" at 115200 baud | Cyclesim + Verilator + synth |
| [rv32_model](rv32_model/) | RV32E golden model and assembler (pure OCaml) | tests |

## Quick start

    make setup         # once per clone: enable the git hooks
    make               # langcheck, dune test, synth, naming check
    make ci            # the above plus the Verilator stage
    make -C uart prog  # flash the UART demo to an iCEstick

Read the UART output with e.g. `picocom -b 115200 /dev/ttyUSB1` (the
iCEstick's FTDI chip exposes two ports; the UART is the second).

## Toolchain

- Local: open the repository in the devcontainer (`.devcontainer/`).
- Claude Code cloud sessions: `.claude/hooks/session-start.sh` installs the
  same tools. The environment's network policy must allow `opam.ocaml.org`
  (and preferably `github.com` and `codeload.github.com`).

Contributors and coding agents: read [AGENTS.md](AGENTS.md).
