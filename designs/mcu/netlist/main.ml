(* Board-level post-synthesis stage (issue #20): the generated iCEstick
   Verilog with the firmware in block RAM (build/direct.v, as for
   board-sim) is synthesised with Yosys and read back into HardCaml; the
   firmware lives only in the SB_RAM40_4K INIT parameters Yosys produced.
   The bench is the one of tb_top.v at pin level: wait for the prompt
   (after the ~22 ms start-up hold), type "hi\r", expect "HI".

     main.exe DIRECT.v DIR

   Flip-flops start as 0 like the silicon, so unlike tb_top.v no power-up
   values are forced; four-state (X) effects stay with board-sim. *)
open! Base
open! Hardcaml
open Stdio
module N = Netlist_sim.With_interface (Mcu_icestick.I) (Mcu_icestick.O)
module Sim = Cyclesim.With_interface (Mcu_icestick.I) (Mcu_icestick.O)

let () =
  let verilog, dir =
    match Sys.get_argv () with
    | [| _; v; d |] -> v, d
    | _ ->
      eprintf "usage: main.exe DIRECT.v DIR\n";
      Stdlib.exit 2
  in
  let m = Netlist_sim.synthesize_file ~dir ~top:"top" verilog in
  let inits = ref [] in
  let sim = Sim.create ~config:Cyclesim.Config.trace_all (N.of_module ~inits m) in
  Netlist_sim.load_ram_init sim !inits;
  let i = Cyclesim.inputs sim in
  let o = Cyclesim.outputs ~clock_edge:Before sim in
  let clocks_per_bit = Mcu_icestick.config.clocks_per_bit in
  let line = Uart_bench.Uart_line.create ~clocks_per_bit in
  let monitor = Uart_bench.Uart_monitor.create ~clocks_per_bit in
  let out = Buffer.create 64 in
  let ms c = Float.of_int c /. Float.of_int (Mcu_icestick.clock_hz / 1000) in
  let typed = ref None in
  let cycle = ref 0 in
  let ends s = String.is_suffix (Buffer.contents out) ~suffix:s in
  let max_cycles = 60 * Mcu_icestick.clock_hz / 1000 in
  let t0 = Unix.gettimeofday () in
  while !cycle < max_cycles && not (Option.is_some !typed && ends "\r\nHI\r\n> ") do
    if Option.is_none !typed && ends "> "
    then (
      eprintf "prompt at %.1f ms\n%!" (ms !cycle);
      Uart_bench.Uart_line.send line "hi\r";
      typed := Some !cycle);
    i.uart_rx := Bits.of_bool (Uart_bench.Uart_line.next line);
    Cyclesim.cycle sim;
    Option.iter (Uart_bench.Uart_monitor.step monitor (Bits.to_bool !(o.uart_tx))) ~f:(Buffer.add_char out);
    Int.incr cycle
  done;
  let led = Bits.to_int !(o.led) in
  eprintf "%.1f ms simulated in %.1f s, output %S, led=%d\n" (ms !cycle)
    (Unix.gettimeofday () -. t0) (Buffer.contents out) led;
  if ends "\r\nHI\r\n> " && led land 7 = 2
  then eprintf "PASS board netlist\n"
  else (
    eprintf "FAIL board netlist\n";
    Stdlib.exit 1)
;;
