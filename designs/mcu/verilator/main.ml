(* Stage 2: the S1 echo test (ip/mcu/test/test_mcu.ml, iCEstick
   configuration) on a Verilator model of the generated Verilog, including
   lockstep against the golden model. The firmware image is the first
   argument. *)
open! Base
open! Hardcaml
open Stdio
module Sim = Hardcaml_verilator.With_interface (Mcu.I) (Mcu.O)
module Bench = Mcu_bench.Bench

let () =
  let image = Bench.firmware (Sys.get_argv ()).(1) in
  let config = Bench.icestick in
  let sim =
    Sim.create
      ~verilator_config:Testlib.Verilator_config.config
      ~clock_names:[ "clock" ]
      (Bench.create config (Scope.create ~flatten_design:true ()))
  in
  let r = Bench.run config sim ~image ~input:"hello\rRV32e!\r" ~cycles:200_000 () in
  let expected = "RV32 MCU ready\r\n> hello\r\nHELLO\r\n> RV32e!\r\nRV32E!\r\n> " in
  match r.mismatch with
  | Some m ->
    eprintf "FAIL mcu lockstep\n%s\n" m;
    Stdlib.exit 1
  | None when String.equal r.output expected && r.leds = 6 ->
    eprintf "PASS mcu echo (%d instructions in lockstep)\n" r.retired
  | None ->
    eprintf "FAIL mcu echo\n  expected: %S\n  actual:   %S leds=%d\n" expected r.output r.leds;
    Stdlib.exit 1
;;
