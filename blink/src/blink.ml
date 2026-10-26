(* LED blinker: a free-running counter whose top bits drive the LEDs. *)
open! Hardcaml
open Signal

module I = struct
  type 'a t = { clock : 'a } [@@deriving hardcaml]
end

module O = struct
  type 'a t = { led : 'a [@bits 5] } [@@deriving hardcaml]
end

(* [counter_bits] is 26 on the board (12 MHz / 2^21 ~ 5.7 Hz on led[0]);
   tests use a small value so that every LED toggles within a few cycles. *)
let create ~counter_bits scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock () in
  let%hw counter = reg_fb spec ~width:counter_bits ~f:(fun d -> d +:. 1) in
  { O.led = select counter (counter_bits - 1) (counter_bits - 5) }
;;

let hierarchical ~counter_bits scope =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ~scope ~name:"blink" (create ~counter_bits)
;;
