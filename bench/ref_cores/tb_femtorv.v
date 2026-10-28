// FemtoRV32 Quark running a firmware image with the MCU's memory map.
// Read data is returned in the cycle after mem_rstrb, never busy.
// ADDR_WIDTH is 32 (default 24) so that the I/O registers at bit 28 are
// reachable; the area figures use the default.
`timescale 1ns/1ns
module tb;
  reg clk = 0, reset_n = 0;
  always #1 clk = ~clk;
  initial #20 reset_n = 1;
  wire [31:0] mem_addr, mem_wdata;
  wire [3:0] mem_wmask;
  wire mem_rstrb;
  reg [31:0] mem_rdata;
`include "tb_mem.vh"
  FemtoRV32 #(.RESET_ADDR(0), .ADDR_WIDTH(32)) cpu (
    .clk(clk), .reset(reset_n), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask), .mem_rdata(mem_rdata), .mem_rstrb(mem_rstrb),
    .mem_rbusy(1'b0), .mem_wbusy(1'b0));
  always @(posedge clk) begin
    if (|mem_wmask) mem_write(mem_addr, mem_wdata, mem_wmask);
    if (mem_rstrb) mem_rdata <= mem_addr[28] ? io_read(mem_addr) : mem[mem_addr[15:2]];
  end
endmodule
