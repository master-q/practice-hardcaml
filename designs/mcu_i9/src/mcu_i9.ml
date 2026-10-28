(* Colorlight i9 v7.2 (Lattice ECP5 LFE5U-45F) top level for the MCU:
   RV32I, 64 KiB RAM, cycle/instret counters, 115200 baud from the 25 MHz
   oscillator through the ext board's DAPLink USB serial port, LED D2.

   Pins (designs/mcu_i9/colorlight_i9.lpf) follow wuxx/Colorlight-FPGA-Projects:
   clock P3, UART TX J17 / RX H18 (as on the i5 ext board), LED D2 on L2.
   The LED is driven active low, as on the other Colorlight modules.

   Bring-up aids (B-0014; docs/BRINGUP_I9.md):
   - the MCU is held in reset for about 21 ms after configuration
     (Mcu.Startup; EXPERIMENT=no-hold removes it);
   - the single LED shows the state: slow blink = clock and bitstream run
     but the firmware has not started; steady on = firmware started (crt0
     sets LEDS bit 0); fast blink = the core halted (trap). *)
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
  let free = Reg_spec.create ~clock:i.clock () in
  let hold = Mcu.Startup.hold ~clock_hz scope ~clock:i.clock in
  let%hw blink = reg_fb free ~width:24 ~f:(fun d -> d +:. 1) in
  let o =
    Mcu.hierarchical
      config
      scope
      { Mcu.I.clock = i.clock
      ; clear = hold
      ; uart_rx = i.uart_rx
      ; load_we = gnd
      ; load_addr = zero Mcu.max_word_bits
      ; load_data = zero 32
      }
  in
  let started = o.leds.:(0) in
  let led = mux2 o.core.halted blink.:(21) (mux2 started vdd (msb blink)) in
  { O.uart_tx = o.uart_tx; led_n = ~:led }
;;

let circuit scope =
  let module C = Circuit.With_interface (I) (O) in
  C.create_exn ~name:"top" (create scope)
;;
