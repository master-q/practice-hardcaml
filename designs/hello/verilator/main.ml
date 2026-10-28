(* Stage 2: run the Cyclesim benches on Verilator-compiled models of the
   generated Verilog; expectations match the S1 tests. *)
open! Base
open! Hardcaml
open Stdio
module Tx_sim = Hardcaml_verilator.With_interface (Uart.Uart_tx.I) (Uart.Uart_tx.O)
module Rx_sim = Hardcaml_verilator.With_interface (Uart.Uart_rx.I) (Uart.Uart_rx.O)
module Hello_sim = Hardcaml_verilator.With_interface (Hello.I) (Hello.O)

let scope () = Scope.create ~flatten_design:true ()
let verilator_config = Testlib.Verilator_config.config

let check name ~expected ~actual =
  if String.equal expected actual
  then eprintf "PASS %s\n" name
  else (
    eprintf "FAIL %s\n  expected: %s\n  actual:   %s\n" name expected actual;
    Stdlib.exit 1)
;;

let () =
  let clocks_per_bit = 4 in
  let sim =
    Tx_sim.create
      ~verilator_config
      ~clock_names:[ "clock" ]
      (Uart.Uart_tx.create ~clocks_per_bit (scope ()))
  in
  check
    "uart_tx"
    ~expected:"OK\n"
    ~actual:(Uart_bench.Bench.uart_tx ~clocks_per_bit sim ~message:"OK\n" ~cycles:200);
  let sim =
    Rx_sim.create
      ~verilator_config
      ~clock_names:[ "clock" ]
      (Uart.Uart_rx.create ~clocks_per_bit (scope ()))
  in
  check
    "uart_rx"
    ~expected:"Hi\r"
    ~actual:(Uart_bench.Bench.uart_rx ~clocks_per_bit sim ~message:"Hi\r" ~cycles:200);
  let sim =
    Hello_sim.create
      ~verilator_config
      ~clock_names:[ "clock" ]
      (Hello_bench.Bench.create (scope ()))
  in
  let bytes, leds = Hello_bench.Bench.run sim ~cycles:330 in
  check
    "hello"
    ~expected:{|"Hi\nHi\n" (0 1 0)|}
    ~actual:(Printf.sprintf "%S %s" bytes (Sexp.to_string [%sexp (leds : int list)]))
;;
