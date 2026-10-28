(* Colorlight i9 v7.2 (Lattice ECP5 LFE5U-45F) top level for the MCU:
   RV32I, 64 KiB RAM, cycle/instret counters, 115200 baud from the 25 MHz
   oscillator through the ext board's DAPLink USB serial port, LED D2.

   Pins (designs/mcu_i9/colorlight_i9.lpf) follow wuxx/Colorlight-FPGA-Projects:
   clock P3, UART TX J17 / RX H18 (as on the i5 ext board), LED D2 on L2.
   The LED is driven active low, as on the other Colorlight modules. *)
open! Base
open! Hardcaml
open Signal

let clock_hz = 25_000_000

let config =
  { Mcu.Config.base = Rv32i
  ; ram_bytes = 65536
  ; clocks_per_bit = clock_hz / 115_200
  ; counters = true
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
    ; led_n : 'a
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
  { O.uart_tx = o.uart_tx; led_n = ~:(o.leds.:(0)) }
;;

let circuit scope =
  let module C = Circuit.With_interface (I) (O) in
  C.create_exn ~name:"top" (create scope)
;;
