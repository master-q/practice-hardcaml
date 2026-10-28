# Colorlight i9 bring-up checklist

For the first session with the Colorlight i9 v7.2 and its ext board
(issue #16). Every step has an expected result; record what happened in
HISTORY.md and any deviation in BUGS.md.

## 0. Before connecting

    git pull
    make ci            # includes the i9 board simulation (~2 min)
    make versions      # note the toolchain in HISTORY.md (B-0015)

## 1. Load and run Dhrystone

    make i9-prog       # openFPGALoader -b colorlight-i9 (CMSIS-DAP, SRAM)
    make i9-term       # picocom -b 115200 /dev/ttyACM0 (I9_TTY=... to change)

Expected:
- LED D2: slow blink for a moment is not visible (the hold is 21 ms);
  it goes steady on (firmware started), then fast blink once Dhrystone has
  finished and the core halted at EBREAK.
- The terminal shows (open it first, then reload with `make i9-prog`):

      dhrystone: runs=500 cycles=... instret=...
      dhrystone: DMIPS/MHz=0.22x

  0.222 is the simulation result with the CI toolchain; other gcc releases
  give slightly different numbers (docs/BENCHMARKS.md).

If the LED keeps blinking slowly: the core did not start (look at the
reset hold, B-0014). If it blinks fast immediately: the core trapped early.
If nothing at all: clock pin or bitstream loading.

## 2. Start-up ablation (does B-0014 exist on the ECP5?)

    make -C designs/mcu_i9 clean && EXPERIMENT=no-hold make i9-prog
    make i9-term

Record whether Dhrystone still runs without the hold. Restore with
`make -C designs/mcu_i9 clean && make i9-prog`.

## 3. Pins and LED polarity

- If the terminal is silent but the LED behaves as expected, check the
  UART pins (TX J17 / RX H18 are taken from the i5 demos) and the tty.
- If the LED is lit when it should be off, the polarity assumption
  (active low) is wrong; fix `designs/mcu_i9/src/mcu_i9.ml`.

## 4. Flash (optional)

    make -C designs/mcu_i9 flash   # writes the SPI flash; survives power cycles

## 5. JTAG

Follow issue #10 (detect the chain, then a minimal JTAGG test design).
