open! Base
open! Hardcaml
open Stdio
module Sim = Cyclesim.With_interface (Mcu.I) (Mcu.O)

(* Inline tests run in _build/default/designs/mcu/test. *)
let echo_bin = "../../../sw/echo.bin"

let%expect_test "echo firmware, in lockstep with the model" =
  let sim = Sim.create (Mcu_bench.Bench.create (Scope.create ~flatten_design:true ())) in
  let r =
    Mcu_bench.Bench.run
      sim
      ~image:(Mcu_bench.Bench.firmware echo_bin)
      ~input:"hello\rRV32e!\r"
      ~cycles:200_000
      ()
  in
  printf "%S\n" r.output;
  printf
    "leds=%d retired=%d trap=%s\n%s\n"
    r.leds
    r.retired
    (Option.value_map r.trap ~default:"none" ~f:Int.to_string)
    (Option.value r.mismatch ~default:"lockstep: ok");
  [%expect {|
    "RV32E MCU ready\r\n> hello\r\nHELLO\r\n> RV32e!\r\nRV32E!\r\n> "
    leds=6 retired=46208 trap=none
    lockstep: ok
    |}]
;;
