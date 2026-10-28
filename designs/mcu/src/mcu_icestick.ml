(* iCEstick top level for the MCU: RV32E, 4 KiB RAM (8 iCE40 block RAMs,
   plus 2 for the register file), 115200 baud at 12 MHz, five LEDs. No
   reset input and no program loader. *)
open! Base
open! Hardcaml
open Signal

let config =
  { Mcu.Config.base = Rv32e
  ; ram_bytes = 4096
  ; clocks_per_bit = 12_000_000 / 115_200
  ; counters = false
  }
;;

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

let create scope (i : _ I.t) =
  let o =
    Mcu.hierarchical
      config
      scope
      { Mcu.I.clock = i.clock
      ; clear = gnd
      ; uart_rx = i.uart_rx
      ; load_we = gnd
      ; load_addr = zero Mcu.max_word_bits
      ; load_data = zero 32
      }
  in
  { O.uart_tx = o.uart_tx; led = o.leds.:[4, 0] }
;;

let circuit scope =
  let module C = Circuit.With_interface (I) (O) in
  C.create_exn ~name:"top" (create scope)
;;
