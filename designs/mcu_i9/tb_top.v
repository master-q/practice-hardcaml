// Board-level simulation of the generated Colorlight i9 top
// (build/direct.v: the same Verilog as the bitstream, firmware loaded by
// $readmemh; here the 50-run Dhrystone image). A UART model on the pins
// prints what the MCU sends; the run passes when the Dhrystone harness has
// printed its DMIPS/MHz line and the core has halted with the LED in its
// "halted" state. Run with `make board-sim`.
`timescale 1ns/1ps
module tb;
  reg clock = 0;
  always #20 clock = ~clock;              // 25 MHz
  localparam BIT = 217 * 40.0;            // 115200 baud, as in the design
  reg uart_rx = 1;
  wire uart_tx, led_n;
  top dut (.clock(clock), .uart_rx(uart_rx), .uart_tx(uart_tx), .led_n(led_n));

  // The registers without a reset start at 0 from the generator's
  // `initial` statements (ip/mcu/gen, B-0023). The start-up hold counter
  // is then moved near the end of the hold to save simulation time (the
  // iCEstick board-sim and the i9 netlist stage run the full hold); #1
  // orders this after the generated initial value.
  initial #1 dut.boot_count = 20'h7ff00;

  integer i, newlines = 0;
  reg [7:0] byte_in;
  reg [8*16-1:0] seen = 0;
  reg dmips_seen = 0;
  initial forever begin
    @(negedge uart_tx);
    #(BIT * 1.5);
    for (i = 0; i < 8; i = i + 1) begin
      byte_in[i] = uart_tx;
      #(BIT);
    end
    $write("%c", byte_in);
    seen = {seen[8*15-1:0], byte_in};
    if (seen[8*10-1:0] == "DMIPS/MHz=") dmips_seen = 1;
  end

  initial begin
    wait (dmips_seen && dut.mcu.core_halted);
    #(BIT * 100);
    $display("\n[tb] halted at %.1f ms", $realtime / 1e6);
    $display("[tb] PASS");
    $finish;
  end

  initial begin
    #200_000_000;                          // 200 ms
    $display("\n[tb] TIMEOUT");
    $display("[tb] FAIL");
    $finish;
  end
endmodule
