# practice-hardcaml

Goal: build a CPU in [HardCaml](https://github.com/janestreet/hardcaml) and run it on the
[iCEstick](https://www.latticesemi.com/en/Products/DevelopmentBoardsAndKits/iCEstick)
(iCE40HX1K-TQ144, 12 MHz) using the open-source Yosys / nextpnr / icestorm flow.

## Toolchain

- Local: open in the devcontainer (`.devcontainer/devcontainer.json`).
- Claude Code cloud sessions: `.claude/hooks/session-start.sh` installs the same tools
  (apt: yosys, nextpnr-ice40, fpga-icestorm; opam switch `hardcaml-5.3.0`).
  The network policy must allow `opam.ocaml.org` (and preferably `github.com`, `codeload.github.com`).

## Projects

| Directory | Description |
|-----------|-------------|
| [blink](blink/) | LED blinker: HardCaml → Verilog → Yosys → nextpnr → icepack |

Build any project with `make -C <dir>` (output in `<dir>/build/top.bin`);
`make -C <dir> prog` writes it to an attached iCEstick with `iceprog`.
