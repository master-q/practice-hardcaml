// Shared by the reference-core testbenches: 64 KiB RAM with one cycle of
// read latency (like the MCU's block RAM) and the MCU's I/O registers
// (sw/common/mcu.h). The UART is always ready; transmitted bytes are
// printed. The run stops after the Dhrystone harness has printed its fourth
// line ("Dhrystones per Second").
reg [31:0] mem [0:16383];
reg [31:0] cycle = 0;
integer newlines = 0;
initial $readmemh(`FIRMWARE_HEX, mem);
always @(posedge clk) cycle <= cycle + 1;

function [31:0] io_read(input [31:0] addr);
  case (addr[4:2])
    3'd1: io_read = 32'h1;    // tx_ready, no rx data
    3'd3: io_read = cycle;
    default: io_read = 0;
  endcase
endfunction

task io_write(input [31:0] addr, input [31:0] data);
  if (addr[4:2] == 3'd0) begin
    $write("%c", data[7:0]);
    if (data[7:0] == 8'h0a) begin
      newlines = newlines + 1;
      if (newlines == 4) begin
        $display("tb: finished at cycle %0d", cycle);
        $finish;
      end
    end
  end
endtask

task mem_write(input [31:0] addr, input [31:0] data, input [3:0] mask);
  if (addr[28]) io_write(addr, data);
  else begin
    if (mask[0]) mem[addr[15:2]][7:0] <= data[7:0];
    if (mask[1]) mem[addr[15:2]][15:8] <= data[15:8];
    if (mask[2]) mem[addr[15:2]][23:16] <= data[23:16];
    if (mask[3]) mem[addr[15:2]][31:24] <= data[31:24];
  end
endtask

initial begin
  #(2 * 5_000_000);
  $display("tb: timeout");
  $finish;
end
