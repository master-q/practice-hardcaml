(* Microcontroller: the rv32 core, RAM in block RAM, a UART, an LED
   register and cycle/instruction counters. Boards instantiate it with a
   [Config.t] (designs/mcu: iCEstick, designs/mcu_i9: Colorlight i9).

   Memory map (see sw/common/mcu.h):
     0x0000_0000 ...            RAM (code, data, stack); aliases above its size
     0x1000_0000  UART data     W: transmit a byte  R: received byte, clears rx_valid
     0x1000_0004  UART status   bit 0 tx_ready, bit 1 rx_valid
     0x1000_0008  LEDS          bits 7..0 (boards use as many as they have)
     0x1000_000c  CYCLE         clock cycles since reset (32 bits, wraps)
     0x1000_0010  INSTRET       instructions retired since reset (32 bits)
                                (both read 0 unless Config.counters)
   Any address with bit 28 set is I/O. Reads have one cycle of latency,
   matching the core's bus.

   The RAM is four byte lanes so stores can write single bytes. The
   register file inside the core takes block RAM too.

   [load_*] writes whole words while the core is held in reset; testbenches
   use it to load programs (board generators put the program into the
   RAM's initial contents instead, see ip/mcu/gen). *)
open! Base
open! Hardcaml
open Signal
module Startup = Startup

module Config = struct
  type t =
    { base : Rv32_model.Isa.base
    ; ram_bytes : int (* power of two *)
    ; clocks_per_bit : int (* clock frequency / UART baud rate *)
    ; counters : bool (* CYCLE and INSTRET; read as 0 when false *)
    }

  let ram_words t = t.ram_bytes / 4
  let word_bits t = Int.ceil_log2 (ram_words t)
end

let max_word_bits = 16

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; uart_rx : 'a
    ; load_we : 'a
    ; load_addr : 'a [@bits max_word_bits]
    ; load_data : 'a [@bits 32]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uart_tx : 'a
    ; leds : 'a [@bits 8]
    ; core : 'a Rv32.Core.O.t [@rtlprefix "core_"]
    }
  [@@deriving hardcaml]
end

let ram_lane_name k = Printf.sprintf "ram_b%d" k

let create (config : Config.t) scope (i : _ I.t) =
  let word_bits = Config.word_bits config in
  assert (word_bits <= max_word_bits);
  let free = Reg_spec.create ~clock:i.clock () in
  let%hw por_count =
    reg_fb free ~width:4 ~f:(fun d -> mux2 (d ==:. 15) d (d +:. 1))
  in
  let%hw clear = (por_count <>:. 15) |: i.clear in
  let spec = Reg_spec.create ~clock:i.clock ~clear () in
  let%hw mem_rdata = wire 32 in
  let core =
    Rv32.Core.hierarchical
      ~base:config.base
      scope
      { Rv32.Core.I.clock = i.clock; clear; mem_rdata }
  in
  let addr = core.mem_addr in
  let%hw is_io = addr.:(28) in
  let%hw word = addr.:[word_bits + 1, 2] in
  let%hw io_reg = addr.:[4, 2] in
  let load_addr = i.load_addr.:[word_bits - 1, 0] in
  (* RAM *)
  let lanes =
    List.init 4 ~f:(fun k ->
      let byte s = s.:[(8 * k) + 7, 8 * k] in
      (Ram.create
         ~name:(ram_lane_name k)
         ~attributes:[ Rtl_attribute.create "no_rw_check" ]
         ~collision_mode:Read_before_write
         ~size:(Config.ram_words config)
         ~write_ports:
           [| { write_clock = i.clock
              ; write_address = mux2 i.load_we load_addr word
              ; write_enable =
                  i.load_we |: (core.mem_write &: ~:is_io &: core.mem_wmask.:(k))
              ; write_data = mux2 i.load_we (byte i.load_data) (byte core.mem_wdata)
              }
           |]
         ~read_ports:[| { read_clock = i.clock; read_address = word; read_enable = vdd } |]
         ()).(0)
      -- (ram_lane_name k ^ "_q"))
  in
  let%hw ram_rdata = concat_lsb lanes in
  (* UART *)
  let io_write r = core.mem_write &: is_io &: (io_reg ==:. r) in
  let io_read r = core.mem_read &: is_io &: (io_reg ==:. r) in
  let clocks_per_bit = config.clocks_per_bit in
  let tx =
    Uart.Uart_tx.hierarchical
      ~clocks_per_bit
      scope
      { Uart.Uart_tx.I.clock = i.clock
      ; clear
      ; data_valid = io_write 0 -- "uart_tx_write"
      ; data = core.mem_wdata.:[7, 0]
      }
  in
  let rx =
    Uart.Uart_rx.hierarchical
      ~clocks_per_bit
      scope
      { Uart.Uart_rx.I.clock = i.clock; clear; rx = i.uart_rx }
  in
  let%hw rx_read = io_read 0 in
  let%hw leds_write = io_write 2 in
  let%hw rx_byte = reg spec ~enable:rx.valid rx.data in
  let%hw rx_valid =
    reg_fb spec ~width:1 ~f:(fun v -> mux2 rx.valid vdd (mux2 rx_read gnd v))
  in
  let%hw leds = reg spec ~enable:leds_write core.mem_wdata.:[7, 0] in
  (* Counters: 64 flip-flops and two adders, too much for the iCEstick
     (BUGS.md B-0009). *)
  let cycle, instret =
    if config.counters
    then (
      let%hw cycle = reg_fb spec ~width:32 ~f:(fun c -> c +:. 1) in
      let%hw instret = reg_fb spec ~width:32 ~f:(fun c -> c +: uresize core.retire 32) in
      cycle, instret)
    else zero 32, zero 32
  in
  let%hw status = rx_valid @: tx.ready in
  let%hw io_rdata =
    reg
      spec
      (mux
         io_reg
         [ uresize rx_byte 32; uresize status 32; uresize leds 32; cycle; instret ])
  in
  let%hw read_io = reg spec (core.mem_read &: is_io) in
  mem_rdata <== mux2 read_io io_rdata ram_rdata;
  { O.uart_tx = tx.tx; leds; core }
;;

let hierarchical config scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"mcu" (create config)
;;
