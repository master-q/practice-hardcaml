open! Base
open! Hardcaml
open Stdio
module Sim = Cyclesim.With_interface (Hello.I) (Hello.O)

let%expect_test "hello repeats its message with a gap" =
  let sim = Sim.create (Hello_bench.Bench.create (Scope.create ~flatten_design:true ())) in
  let bytes, leds = Hello_bench.Bench.run sim ~cycles:330 in
  printf "%S %s\n" bytes (Sexp.to_string [%sexp (leds : int list)]);
  [%expect {| "Hi\nHi\n" (0 1 0) |}]
;;
