open! Base
open! Hardcaml
open Stdio
module Tx_sim = Cyclesim.With_interface (Uart.Uart_tx.I) (Uart.Uart_tx.O)
module Rx_sim = Cyclesim.With_interface (Uart.Uart_rx.I) (Uart.Uart_rx.O)

let clocks_per_bit = 4
let scope () = Scope.create ~flatten_design:true ()

let%expect_test "uart_tx sends queued bytes back to back" =
  let sim = Tx_sim.create (Uart.Uart_tx.create ~clocks_per_bit (scope ())) in
  printf "%S\n" (Uart_bench.Bench.uart_tx ~clocks_per_bit sim ~message:"OK\n" ~cycles:200);
  [%expect {| "OK\n" |}]
;;

let%expect_test "uart_rx receives back-to-back bytes" =
  let sim = Rx_sim.create (Uart.Uart_rx.create ~clocks_per_bit (scope ())) in
  printf
    "%S\n"
    (Uart_bench.Bench.uart_rx ~clocks_per_bit sim ~message:"Hi\x00\xff\r" ~cycles:300);
  [%expect {| "Hi\000\255\r" |}]
;;

let%expect_test "uart_rx at the board's divider" =
  let clocks_per_bit = 12_000_000 / 115_200 in
  let sim = Rx_sim.create (Uart.Uart_rx.create ~clocks_per_bit (scope ())) in
  printf
    "%S\n"
    (Uart_bench.Bench.uart_rx ~clocks_per_bit sim ~message:"ok" ~cycles:(25 * clocks_per_bit));
  [%expect {| "ok" |}]
;;

(* Waveform of one frame: start bit, 0x55 = 1,0,1,0,1,0,1,0 LSB first, stop
   bit. Read it as documentation of the transmitter's timing. *)
let%expect_test "uart_tx waveform" =
  let open Hardcaml_waveterm in
  let sim = Tx_sim.create (Uart.Uart_tx.create ~clocks_per_bit:2 (scope ())) in
  let waves, sim = Waveform.create sim in
  let i = Cyclesim.inputs sim in
  i.data := Bits.of_int ~width:8 0x55;
  i.data_valid := Bits.vdd;
  Cyclesim.cycle sim;
  i.data_valid := Bits.gnd;
  for _ = 1 to 22 do
    Cyclesim.cycle sim
  done;
  Testlib.Ascii_wave.print
    ~signals:[ "data_valid", Bit; "data", Hex; "ready", Bit; "tx", Bit ]
    ~display_height:13
    waves;
  [%expect {|
    +Signals-----------++Waves-----------------------------------------------------+
    |data_valid        ||--+                                                       |
    |                  ||  +-------------------------------------------            |
    |                  ||----------------------------------------------            |
    |data              || 55                                                       |
    |                  ||----------------------------------------------            |
    |ready             ||--+                                       +---            |
    |                  ||  +---------------------------------------+               |
    |tx                ||--+   +---+   +---+   +---+   +---+   +-------            |
    |                  ||  +---+   +---+   +---+   +---+   +---+                   |
    |                  ||                                                          |
    |                  ||                                                          |
    +------------------++----------------------------------------------------------+
    |}]
;;
