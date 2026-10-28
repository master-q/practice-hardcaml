(* Top level: repeatedly send [message] over the iCEstick's FTDI UART
   (channel B), pausing 2^[gap_bits] cycles between messages. led toggles
   once per message. There is no reset button, so a power-on reset is
   generated from the configuration-time zero state of the flip-flops. *)
open! Base
open! Hardcaml
open Signal

module I = struct
  type 'a t = { clock : 'a } [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { uart_tx : 'a
    ; led : 'a
    }
  [@@deriving hardcaml]
end

let create ~clocks_per_bit ~gap_bits ~message scope (i : _ I.t) =
  let free = Reg_spec.create ~clock:i.clock () in
  let%hw por_count =
    reg_fb free ~width:4 ~f:(fun d -> mux2 (d ==:. 15) d (d +:. 1))
  in
  let%hw clear = por_count <>:. 15 in
  let spec = Reg_spec.create ~clock:i.clock ~clear () in
  let length = String.length message in
  let index_bits = Int.max 1 (Int.ceil_log2 length) in
  let data_valid = wire 1 in
  let tx_ready = wire 1 in
  let%hw_var index = Always.Variable.reg ~width:index_bits spec in
  let%hw_var gap = Always.Variable.reg ~width:gap_bits spec in
  let%hw_var waiting = Always.Variable.reg ~width:1 spec in
  let%hw_var led = Always.Variable.reg ~width:1 spec in
  let last = index.value ==:. length - 1 in
  Always.(
    compile
      [ if_
          waiting.value
          [ gap <-- gap.value +:. 1
          ; when_ (gap.value ==:. -1) [ waiting <-- gnd ]
          ]
          [ when_
              tx_ready
              [ index <-- mux2 last (zero index_bits) (index.value +:. 1)
              ; when_ last [ waiting <-- vdd; led <-- ~:(led.value) ]
              ]
          ]
      ]);
  data_valid <== (tx_ready &: ~:(waiting.value));
  let rom =
    List.init length ~f:(fun k -> of_char (String.get message k))
  in
  let%hw tx_byte = mux index.value rom in
  let tx =
    Uart.Uart_tx.hierarchical
      ~clocks_per_bit
      scope
      { Uart.Uart_tx.I.clock = i.clock; clear; data_valid; data = tx_byte }
  in
  tx_ready <== tx.ready;
  { O.uart_tx = tx.tx; led = led.value }
;;

let hierarchical ~clocks_per_bit ~gap_bits ~message scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"hello" (create ~clocks_per_bit ~gap_bits ~message)
;;
