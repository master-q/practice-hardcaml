(* Testbenches shared by every simulation stage: Cyclesim (dune test) and
   Verilator (make verilate). Each takes an already-built simulator, so the
   stimulus and the checked result are identical across stages. *)
open! Base
open! Hardcaml

let clocks_per_bit = 4

(* Feed [message] into uart_tx as fast as it is accepted and return the bytes
   decoded from the tx line. *)
let uart_tx (sim : (_ Uart.Uart_tx.I.t, _ Uart.Uart_tx.O.t) Cyclesim.t) ~message ~cycles =
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs sim in
  let pending = ref (String.to_list message) in
  let trace =
    Array.init cycles ~f:(fun _ ->
      (match !pending with
       | c :: rest when Bits.to_bool !(o.ready) ->
         i.data_valid := Bits.vdd;
         i.data := Bits.of_char c;
         pending := rest
       | _ -> i.data_valid := Bits.gnd);
      Cyclesim.cycle sim;
      Bits.to_bool !(o.tx))
  in
  Uart_decode.decode ~clocks_per_bit trace
;;

let hello_gap_bits = 6
let hello_message = "Hi\n"

(* Run the hello top level; return the decoded bytes and the led history
   with consecutive duplicates removed. *)
let hello (sim : (_ Uart.Hello.I.t, _ Uart.Hello.O.t) Cyclesim.t) ~cycles =
  let o = Cyclesim.outputs sim in
  let leds = ref [] in
  let trace =
    Array.init cycles ~f:(fun _ ->
      Cyclesim.cycle sim;
      leds := Bits.to_int !(o.led) :: !leds;
      Bits.to_bool !(o.uart_tx))
  in
  ( Uart_decode.decode ~clocks_per_bit trace
  , List.remove_consecutive_duplicates (List.rev !leds) ~equal:Int.equal )
;;

let create_hello scope =
  Uart.Hello.create ~clocks_per_bit ~gap_bits:hello_gap_bits ~message:hello_message scope
;;

let create_uart_tx scope = Uart.Uart_tx.create ~clocks_per_bit scope
