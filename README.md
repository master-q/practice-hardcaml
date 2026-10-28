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

    make setup     # once per clone: enable the git hooks
    make           # langcheck, tests, synthesis, S3 checks
    make ci        # the above plus the Verilator stage

## Running the MCU on an iCEstick

    make mcu-prog  # build designs/mcu with sw/echo.bin and flash it
    make mcu-term  # picocom -b 115200 /dev/ttyUSB1 (override with TTY=...)

The iCEstick's FTDI chip exposes two serial ports; the UART is the second
(usually `/dev/ttyUSB1`). After reset the MCU prints `RV32E MCU ready` and
a `> ` prompt. Type a line and press Enter: it answers in upper case and
shows the line length on the LEDs. Leave picocom with Ctrl-A Ctrl-X.

Changing only the firmware (`sw/`) is fast: the hardware is synthesised
once with placeholder RAM contents, and `icebram` writes the new program
into the existing bitstream. `make mcu-prog` after editing
`sw/echo/main.c` takes about a second plus flashing; only HDL changes
re-run Yosys and nextpnr (about 16 s).

## Toolchain

- Local: open the repository in the devcontainer (`.devcontainer/`).
- Claude Code cloud sessions: `.claude/hooks/session-start.sh` installs the
  same tools. The environment's network policy must allow `opam.ocaml.org`
  (and preferably `github.com` and `codeload.github.com`).

Contributors and coding agents: read [AGENTS.md](AGENTS.md).
