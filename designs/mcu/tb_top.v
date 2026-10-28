// Board-level simulation of the generated iCEstick top (build/direct.v:
// the same Verilog as the bitstream, firmware loaded by $readmemh). A UART
// model on the pins types "hi\r" after the banner and prints what the MCU
// sends. Run with `make board-sim`.
`timescale 1ns/1ps
module tb;
  reg clock = 0;
  always #41.667 clock = ~clock;          // 12 MHz
  localparam BIT = 104 * 83.333;          // 115200 baud, as in the design
  reg uart_rx = 1;
  wire uart_tx;
  wire [4:0] led;
  top dut (.clock(clock), .uart_rx(uart_rx), .uart_tx(uart_tx), .led(led));

  // iCE40 flip-flops power up as 0. HardCaml v0.17 cannot express initial
  // register values, so the registers without a reset start as X in a
  // four-state simulator; give them the silicon's power-up value.
  initial begin
    dut.boot_count = 0;
    dut.heartbeat = 0;
    dut.mcu.por_count = 0;
  end

  // Receiver: print each byte the MCU transmits.
  integer i;
  reg [7:0] byte_in;
  reg [8*64-1:0] seen = 0;
  initial forever begin
    @(negedge uart_tx);
    #(BIT * 1.5);
    for (i = 0; i < 8; i = i + 1) begin
      byte_in[i] = uart_tx;
      #(BIT);
    end
    $write("%c", byte_in);
    seen = {seen[8*63-1:0], byte_in};
  end

  task send(input [7:0] c);
    integer k;
    begin
      uart_rx = 0; #(BIT);
      for (k = 0; k < 8; k = k + 1) begin uart_rx = c[k]; #(BIT); end
      uart_rx = 1; #(BIT * 2);
    end
  endtask

  initial begin
    // Wait for the prompt "> " (after the ~22 ms power-on hold), then type.
    wait (seen[15:0] == "> ");
    $display("\n[tb] prompt seen at %.1f ms, led=%b", $realtime / 1e6, led);
    send("h"); send("i"); send(8'h0d);
    // The answer ends with the upper-cased line and a new prompt:
    // "\r\nHI\r\n> " (Verilog strings have no \r escape, hence hex).
    wait (seen[8*8-1:0] == 64'h0d0a48490d0a3e20);
    #(BIT * 20);
    $display("\n[tb] done at %.1f ms, led=%b", $realtime / 1e6, led);
    if (seen[8*8-1:0] == 64'h0d0a48490d0a3e20 && led[2:0] == 3'd2) $display("[tb] PASS");
    else $display("[tb] FAIL: last bytes %h", seen[8*8-1:0]);
    $finish;
  end

  initial begin
    #100_000_000;                          // 100 ms
    $display("\n[tb] TIMEOUT, led=%b, last bytes %h", led, seen[8*12-1:0]);
    $display("[tb] FAIL");
    $finish;
  end
endmodule
