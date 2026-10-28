(* RV32E microcontroller: the rv32e core, 4 KiB of RAM in block RAM, a UART
   and an LED register.

   Memory map (see sw/common/mcu.h):
     0x0000_0000 - 0x0000_0fff  RAM (code, data, stack); aliases above 4 KiB
     0x1000_0000  UART data   W: transmit a byte  R: received byte, clears rx_valid
     0x1000_0004  UART status bit 0 tx_ready, bit 1 rx_valid
     0x1000_0008  LEDS        bits 4..0
   Any address with bit 28 set is I/O. Reads have one cycle of latency,
   matching the core's bus.

   The RAM is four 1024 x 8 byte lanes so stores can write single bytes.
   Each lane maps onto two iCE40 SB_RAM40_4K blocks; the 16 x 32 register
   file inside the core takes two more, so the design needs 10 BRAMs.

   [load_*] writes whole words while the core is held in reset; testbenches
   use it to load programs (the board generator instead puts the program
   into the BRAMs' initial contents, see bin/main.ml). *)
open! Base
open! Hardcaml
open Signal

let ram_words = 1024

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; uart_rx : 'a
    ; load_we : 'a
    ; load_addr : 'a [@bits 10]
    ; load_data : 'a [@bits 32]
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uart_tx : 'a
    ; leds : 'a [@bits 5]
    ; core : 'a Rv32e.Core.O.t [@rtlprefix "core_"]
    }
  [@@deriving hardcaml]
end

let ram_lane_name k = Printf.sprintf "ram_b%d" k

let create ~clocks_per_bit scope (i : _ I.t) =
  let free = Reg_spec.create ~clock:i.clock () in
  let%hw por_count =
    reg_fb free ~width:4 ~f:(fun d -> mux2 (d ==:. 15) d (d +:. 1))
  in
  let%hw clear = (por_count <>:. 15) |: i.clear in
  let spec = Reg_spec.create ~clock:i.clock ~clear () in
  let mem_rdata = wire 32 in
  let core =
    Rv32e.Core.hierarchical scope { Rv32e.Core.I.clock = i.clock; clear; mem_rdata }
  in
  let addr = core.mem_addr in
  let is_io = addr.:(28) in
  let word = addr.:[11, 2] in
  let io_reg = addr.:[3, 2] in
  (* RAM *)
  let lanes =
    List.init 4 ~f:(fun k ->
      let byte s = s.:[(8 * k) + 7, 8 * k] in
      (Ram.create
         ~name:(ram_lane_name k)
         ~attributes:[ Rtl_attribute.create "no_rw_check" ]
         ~collision_mode:Read_before_write
         ~size:ram_words
         ~write_ports:
           [| { write_clock = i.clock
              ; write_address = mux2 i.load_we i.load_addr word
              ; write_enable =
                  i.load_we |: (core.mem_write &: ~:is_io &: core.mem_wmask.:(k))
              ; write_data = mux2 i.load_we (byte i.load_data) (byte core.mem_wdata)
              }
           |]
         ~read_ports:[| { read_clock = i.clock; read_address = word; read_enable = vdd } |]
         ()).(0)
      -- (ram_lane_name k ^ "_q"))
  in
  let ram_rdata = concat_lsb lanes in
  (* UART *)
  let io_write r = core.mem_write &: is_io &: (io_reg ==:. r) in
  let io_read r = core.mem_read &: is_io &: (io_reg ==:. r) in
  let tx =
    Uart.Uart_tx.hierarchical
      ~clocks_per_bit
      scope
      { Uart.Uart_tx.I.clock = i.clock
      ; clear
      ; data_valid = io_write 0
      ; data = core.mem_wdata.:[7, 0]
      }
  in
  let rx =
    Uart.Uart_rx.hierarchical
      ~clocks_per_bit
      scope
      { Uart.Uart_rx.I.clock = i.clock; clear; rx = i.uart_rx }
  in
  let%hw rx_byte = reg spec ~enable:rx.valid rx.data in
  let%hw rx_valid =
    reg_fb spec ~width:1 ~f:(fun v -> mux2 rx.valid vdd (mux2 (io_read 0) gnd v))
  in
  let%hw leds = reg spec ~enable:(io_write 2) core.mem_wdata.:[4, 0] in
  let status = rx_valid @: tx.ready in
  let%hw io_rdata =
    reg
      spec
      (mux io_reg [ uresize rx_byte 32; uresize status 32; uresize leds 32; zero 32 ])
  in
  let%hw read_io = reg spec (core.mem_read &: is_io) in
  mem_rdata <== mux2 read_io io_rdata ram_rdata;
  { O.uart_tx = tx.tx; leds; core }
;;

let hierarchical ~clocks_per_bit scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"mcu" (create ~clocks_per_bit)
;;

module Mcu_I = I

(* The iCEstick top level: no reset input, no program loader. *)
module Board = struct
  module I = struct
    type 'a t =
      { clock : 'a
      ; uart_rx : 'a
      }
    [@@deriving hardcaml]
  end

  module O = struct
    type 'a t =
      { uart_tx : 'a
      ; led : 'a [@bits 5]
      }
    [@@deriving hardcaml]
  end

  let create ~clocks_per_bit scope (i : _ I.t) =
    let o =
      hierarchical
        ~clocks_per_bit
        scope
        { Mcu_I.clock = i.clock
        ; clear = gnd
        ; uart_rx = i.uart_rx
        ; load_we = gnd
        ; load_addr = zero 10
        ; load_data = zero 32
        }
    in
    { O.uart_tx = o.uart_tx; led = o.leds }
  ;;
end
