// PicoRV32 (configured as in riscv-ice40: ENABLE_COUNTERS=1, otherwise
// defaults) running a firmware image with the MCU's memory map.
`timescale 1ns/1ns
module tb;
  reg clk = 0, resetn = 0;
  always #1 clk = ~clk;
  initial #20 resetn = 1;
  wire mem_valid, mem_instr;
  reg mem_ready = 0;
  wire [31:0] mem_addr, mem_wdata;
  wire [3:0] mem_wstrb;
  reg [31:0] mem_rdata;
`include "tb_mem.vh"
  picorv32 #(.ENABLE_COUNTERS(1), .PROGADDR_RESET(0)) cpu (
    .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_instr(mem_instr),
    .mem_ready(mem_ready), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata));
  // Answer each request in the following cycle.
  always @(posedge clk) begin
    mem_ready <= 0;
    if (mem_valid && !mem_ready) begin
      mem_ready <= 1;
      if (|mem_wstrb) mem_write(mem_addr, mem_wdata, mem_wstrb);
      else mem_rdata <= mem_addr[28] ? io_read(mem_addr) : mem[mem_addr[15:2]];
    end
  end
endmodule
