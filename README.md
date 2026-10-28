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

| Directory | Description | Stages |
|-----------|-------------|--------|
| [ip/uart](ip/uart/) | 8N1 UART transmitter and receiver | S1, S2 |
| [ip/rv32e](ip/rv32e/) | Multi-cycle RV32E core | S0 (SAT proofs), S1 (lockstep, random programs) |
| [designs/blink](designs/blink/) | LED blinker | S1, S3 |
| [designs/hello](designs/hello/) | Prints "Hello, iCEstick!" at 115200 baud | S1, S2, S3 |
| [designs/mcu](designs/mcu/) | RV32E MCU running C firmware (UART echo) | S1, S2, S3 |
| [models/rv32_model](models/rv32_model/) | RV32E golden model and assembler | tests |
| [sw](sw/) | MCU firmware (C, built with riscv64-unknown-elf-gcc) | -- |

No design has been run on a board yet (S4).

## Quick start

    make setup               # once per clone: enable the git hooks
    make                     # langcheck, tests, synthesis, S3 checks
    make ci                  # the above plus the Verilator stage
    make -C designs/mcu prog # flash the MCU with the echo firmware

Then talk to the MCU with e.g. `picocom -b 115200 /dev/ttyUSB1` (the
iCEstick's FTDI chip exposes two ports; the UART is the second). Type a
line and press Enter; it answers in upper case and shows the line length on
the LEDs.

## Toolchain

- Local: open the repository in the devcontainer (`.devcontainer/`).
- Claude Code cloud sessions: `.claude/hooks/session-start.sh` installs the
  same tools. The environment's network policy must allow `opam.ocaml.org`
  (and preferably `github.com` and `codeload.github.com`).

Contributors and coding agents: read [AGENTS.md](AGENTS.md).
