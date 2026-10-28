open! Base
open! Hardcaml
open Stdio
module Sim = Cyclesim.With_interface (Mcu.I) (Mcu.O)
module Bench = Mcu_bench.Bench

(* Inline tests run in _build/default/ip/mcu/test. *)
let firmware name = Bench.firmware ("../../../sw/" ^ name)

let run config ~image ~input ~cycles =
  let sim = Sim.create (Bench.create config (Scope.create ~flatten_design:true ())) in
  Bench.run config sim ~image ~input ~cycles ()
;;

let print_result (r : Bench.result) =
  printf "%S\n" r.output;
  printf
    "leds=%d retired=%d trap=%s\n%s\n"
    r.leds
    r.retired
    (Option.value_map r.trap ~default:"none" ~f:Int.to_string)
    (Option.value r.mismatch ~default:"lockstep: ok")
;;

let%expect_test "iCEstick configuration: RV32E echo firmware, in lockstep" =
  print_result
    (run
       Bench.icestick
       ~image:(firmware "echo_rv32e.bin")
       ~input:"hello\rRV32e!\r"
       ~cycles:200_000);
  [%expect
    {|
    "RV32 MCU ready\r\n> hello\r\nHELLO\r\n> RV32e!\r\nRV32E!\r\n> "
    leds=6 retired=46207 trap=none
    lockstep: ok
    |}]
;;

let%expect_test "i9 configuration: RV32I echo firmware, in lockstep" =
  print_result
    (run Bench.i9 ~image:(firmware "echo_rv32i.bin") ~input:"rv32i\r" ~cycles:200_000);
  [%expect {|
    "RV32 MCU ready\r\n> rv32i\r\nRV32I\r\n> "
    leds=5 retired=46184 trap=none
    lockstep: ok
    |}]
;;

let%expect_test "i9 configuration: Dhrystone (50 runs), in lockstep" =
  let r =
    run Bench.i9 ~image:(firmware "dhrystone_sim.bin") ~input:"" ~cycles:3_000_000
  in
  print_result r;
  [%expect {|
    "dhrystone: runs=50 cycles=128090 instret=30133\r\nMicroseconds for one run through Dhrystone: 2560\r\nDhrystones per Second:                      390\r\n"
    leds=0 retired=46999 trap=2
    lockstep: ok
    |}]
;;
