(* Board-level post-synthesis stage for the Colorlight i9 (ECP5): the
   generated top-level Verilog with the firmware in block RAM is
   synthesised with synth_ecp5 and read back into HardCaml; the firmware
   lives only in the DP16KD INITVAL parameters Yosys produced, and the
   start-up hold runs in full (no forced counter values: TRELLIS_FFs power
   up at their set/reset value, as on the chip). The firmware is sw/irq:
   wait for the prompt, type "irq\r" one key per echo, expect "IRQ", and
   the LED steady on (firmware started, not halted).

     main.exe TOP.v DIR *)
open! Base
open! Hardcaml
open Stdio
module N = Netlist_sim.With_interface (Mcu_i9.I) (Mcu_i9.O)
module Sim = Cyclesim.With_interface (Mcu_i9.I) (Mcu_i9.O)

let () =
  let verilog, dir =
    match Sys.get_argv () with
    | [| _; v; d |] -> v, d
    | _ ->
      eprintf "usage: main.exe TOP.v DIR\n";
      Stdlib.exit 2
  in
  let m = Netlist_sim.synthesize_file ~arch:Ecp5 ~dir ~top:"top" verilog in
  let inits = ref [] in
  let sim = Sim.create ~config:Cyclesim.Config.trace_all (N.of_module ~inits m) in
  Netlist_sim.load_ram_init sim !inits;
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs ~clock_edge:Before sim in
  let clocks_per_bit = Mcu_i9.config.clocks_per_bit in
  let line = Uart_bench.Uart_line.create ~clocks_per_bit in
  let monitor = Uart_bench.Uart_monitor.create ~clocks_per_bit in
  let out = Buffer.create 128 in
  let ms c = Float.of_int c /. Float.of_int (Mcu_i9.clock_hz / 1000) in
  let ends s = String.is_suffix (Buffer.contents out) ~suffix:s in
  let keys = ref (String.to_list "irq\r") in
  let expect = ref "> " in
  let first_output = ref None in
  let cycle = ref 0 in
  let max_cycles = 80 * Mcu_i9.clock_hz / 1000 in
  let done_ = "> irq\r\nIRQ\r\n> " in
  let t0 = Unix.gettimeofday () in
  while !cycle < max_cycles && not (List.is_empty !keys && ends done_) do
    (match !keys with
     | c :: rest when ends !expect && Uart_bench.Uart_line.idle line ->
       Uart_bench.Uart_line.send line (String.of_char c);
       keys := rest;
       expect := if Char.equal c '\r' then "> " else String.of_char c
     | _ -> ());
    i.uart_rx := Bits.of_bool (Uart_bench.Uart_line.next line);
    Cyclesim.cycle sim;
    Option.iter (Uart_bench.Uart_monitor.step monitor (Bits.to_bool !(o.uart_tx))) ~f:(fun c ->
      if Option.is_none !first_output then first_output := Some !cycle;
      Buffer.add_char out c);
    Int.incr cycle
  done;
  let led_on = not (Bits.to_bool !(o.led_n)) in
  let first_ms = Option.value_map !first_output ~default:Float.nan ~f:ms in
  eprintf
    "%.1f ms simulated in %.1f s; first byte at %.1f ms; output %S; led %s\n"
    (ms !cycle)
    (Unix.gettimeofday () -. t0)
    first_ms
    (Buffer.contents out)
    (if led_on then "on" else "off");
  if ends done_
     && String.is_prefix (Buffer.contents out) ~prefix:"irq: timer ok, software ok, ecall ok"
     && led_on
     && Float.(first_ms >= of_int Mcu.Startup.min_hold_ms)
  then eprintf "PASS i9 board netlist\n"
  else (
    eprintf "FAIL i9 board netlist\n";
    Stdlib.exit 1)
;;
