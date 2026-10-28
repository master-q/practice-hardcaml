(* UART testbenches shared by every simulation stage. Each takes an
   already-built simulator, so stimulus and checks are identical whether it
   is Cyclesim or Verilator. *)
open! Base
open! Hardcaml

(* Feed [message] into uart_tx as fast as it is accepted and return the bytes
   decoded from the tx line. *)
let uart_tx
  ~clocks_per_bit
  (sim : (_ Uart.Uart_tx.I.t, _ Uart.Uart_tx.O.t) Cyclesim.t)
  ~message
  ~cycles
  =
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

(* Drive [message] into uart_rx's line and collect the bytes it reports. *)
let uart_rx
  ~clocks_per_bit
  (sim : (_ Uart.Uart_rx.I.t, _ Uart.Uart_rx.O.t) Cyclesim.t)
  ~message
  ~cycles
  =
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs sim in
  let line = Uart_line.create ~clocks_per_bit in
  Uart_line.send line message;
  let received = Buffer.create 16 in
  for _ = 1 to cycles do
    i.rx := Bits.of_bool (Uart_line.next line);
    Cyclesim.cycle sim;
    if Bits.to_bool !(o.valid) then Buffer.add_char received (Bits.to_char !(o.data))
  done;
  Buffer.contents received
;;
