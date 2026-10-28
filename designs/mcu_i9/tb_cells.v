// Behavioural stand-in for the ECP5 PLL in the Icarus board simulation
// (Yosys's ECP5 cell library has no simulation model for EHXPLLL). CLKOP
// runs at CLKI * CLKFB_DIV / CLKI_DIV, assuming a 25 MHz CLKI; LOCK rises
// after LOCK_NS. Phase relations are not modelled: the design uses only
// CLKOP. The netlist stage (testlib/netlist) models it as CLKOP = CLKI.
`timescale 1ns/1ps
module EHXPLLL #(
  parameter PLLRST_ENA = "DISABLED", parameter INTFB_WAKE = "DISABLED",
  parameter STDBY_ENABLE = "DISABLED", parameter DPHASE_SOURCE = "DISABLED",
  parameter OUTDIVIDER_MUXA = "DIVA", parameter OUTDIVIDER_MUXB = "DIVB",
  parameter OUTDIVIDER_MUXC = "DIVC", parameter OUTDIVIDER_MUXD = "DIVD",
  parameter integer CLKI_DIV = 1, parameter CLKOP_ENABLE = "ENABLED",
  parameter integer CLKOP_DIV = 8, parameter integer CLKOP_CPHASE = 0,
  parameter integer CLKOP_FPHASE = 0, parameter FEEDBK_PATH = "CLKOP",
  parameter integer CLKFB_DIV = 1
) (
  input RST, STDBY, CLKI, CLKFB, PHASESEL0, PHASESEL1, PHASEDIR, PHASESTEP,
  input PHASELOADREG, PLLWAKESYNC, ENCLKOP,
  output reg CLKOP = 0, output reg LOCK = 0
);
  localparam real HALF_NS = 20.0 * CLKI_DIV / CLKFB_DIV;  // 25 MHz in
  localparam real LOCK_NS = 50000.0;                      // 50 us
  always #(HALF_NS) CLKOP = ~CLKOP;
  initial #(LOCK_NS) LOCK = 1;
endmodule
