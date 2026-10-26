open! Base
open! Hardcaml
open Stdio
module Bench = Uart_bench.Bench
module Tx_sim = Cyclesim.With_interface (Uart.Uart_tx.I) (Uart.Uart_tx.O)
module Hello_sim = Cyclesim.With_interface (Uart.Hello.I) (Uart.Hello.O)

let scope () = Scope.create ~flatten_design:true ()

let%expect_test "uart_tx sends queued bytes back to back" =
  let sim = Tx_sim.create (Bench.create_uart_tx (scope ())) in
  printf "%S\n" (Bench.uart_tx sim ~message:"OK\n" ~cycles:200);
  [%expect {| "OK\n" |}]
;;

let%expect_test "hello repeats its message with a gap" =
  let sim = Hello_sim.create (Bench.create_hello (scope ())) in
  let bytes, leds = Bench.hello sim ~cycles:330 in
  printf "%S %s\n" bytes (Sexp.to_string [%sexp (leds : int list)]);
  [%expect {| "Hi\nHi\n" (0 1 0) |}]
;;
