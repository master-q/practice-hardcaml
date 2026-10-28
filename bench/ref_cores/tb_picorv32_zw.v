// PicoRV32 as tb_picorv32.v, but with a zero-wait memory (mem_ready in the
// same cycle as mem_valid). This is the best case for PicoRV32 and is what
// its look-ahead interface achieves with block RAM in riscv-ice40's SoC.
`timescale 1ns/1ns
module tb;
  reg clk = 0, resetn = 0;
  always #1 clk = ~clk;
  initial #20 resetn = 1;
  wire mem_valid, mem_instr;
  wire [31:0] mem_addr, mem_wdata;
  wire [3:0] mem_wstrb;
`include "tb_mem.vh"
  wire [31:0] mem_rdata = mem_addr[28] ? io_read(mem_addr) : mem[mem_addr[15:2]];
  picorv32 #(.ENABLE_COUNTERS(1), .PROGADDR_RESET(0)) cpu (
    .clk(clk), .resetn(resetn), .mem_valid(mem_valid), .mem_instr(mem_instr),
    .mem_ready(mem_valid), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata));
  always @(posedge clk)
    if (mem_valid && |mem_wstrb) mem_write(mem_addr, mem_wdata, mem_wstrb);
endmodule
