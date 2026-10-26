(* Stage 2: run the shared testbenches on Verilator-compiled models of the
   generated Verilog and check they agree with the Cyclesim expectations in
   ../test/test_uart.ml. *)
open! Base
open! Hardcaml
open Stdio
module Bench = Uart_bench.Bench
module Tx_sim = Hardcaml_verilator.With_interface (Uart.Uart_tx.I) (Uart.Uart_tx.O)
module Hello_sim = Hardcaml_verilator.With_interface (Uart.Hello.I) (Uart.Hello.O)

let scope () = Scope.create ~flatten_design:true ()

(* Ubuntu 24.04 and Debian trixie ship Verilator 5. [verbose = true] works
   around a hardcaml_verilator v0.17.0 bug: in quiet mode it appends the
   bash-only redirect "&>file" and runs the command with /bin/sh, which on
   Debian/Ubuntu (dash) backgrounds the build and races the final link.
   Build output therefore goes to stdout; results go to stderr. *)
let verilator_config =
  { Hardcaml_verilator.Config.default with verilator_version = V5; verbose = true }
;;

let check name ~expected ~actual =
  if String.equal expected actual
  then eprintf "PASS %s\n" name
  else (
    eprintf "FAIL %s\n  expected: %s\n  actual:   %s\n" name expected actual;
    Stdlib.exit 1)
;;

let () =
  let sim = Tx_sim.create ~verilator_config ~clock_names:[ "clock" ] (Bench.create_uart_tx (scope ())) in
  check
    "uart_tx"
    ~expected:"OK\n"
    ~actual:(Bench.uart_tx sim ~message:"OK\n" ~cycles:200);
  let sim = Hello_sim.create ~verilator_config ~clock_names:[ "clock" ] (Bench.create_hello (scope ())) in
  let bytes, leds = Bench.hello sim ~cycles:330 in
  check
    "hello"
    ~expected:{|"Hi\nHi\n" (0 1 0)|}
    ~actual:(Printf.sprintf "%S %s" bytes (Sexp.to_string [%sexp (leds : int list)]))
;;
