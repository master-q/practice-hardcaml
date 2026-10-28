(* Testbench for the hello top level, shared by Cyclesim and Verilator. *)
open! Base
open! Hardcaml

let clocks_per_bit = 4
let gap_bits = 6
let message = "Hi\n"
let create scope = Hello.create ~clocks_per_bit ~gap_bits ~message scope

(* Return the decoded bytes and the led history without repeats. *)
let run (sim : (_ Hello.I.t, _ Hello.O.t) Cyclesim.t) ~cycles =
  let o = Cyclesim.outputs sim in
  let leds = ref [] in
  let trace =
    Array.init cycles ~f:(fun _ ->
      Cyclesim.cycle sim;
      leds := Bits.to_int !(o.led) :: !leds;
      Bits.to_bool !(o.uart_tx))
  in
  ( Uart_bench.Uart_decode.decode ~clocks_per_bit trace
  , List.remove_consecutive_duplicates (List.rev !leds) ~equal:Int.equal )
;;
