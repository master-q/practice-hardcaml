(* Post-synthesis stage (issue #20): synthesise the MCU (with the load
   port) with Yosys, read the netlist back into HardCaml and run the S1
   bench on it, including lockstep against the golden model.

     main.exe [--ecp5] [--invert-luts] [--verilator] FIRMWARE.bin DIR

   Default: the iCEstick configuration (synth_ice40) with the echo
   firmware. --ecp5: the i9 configuration (synth_ecp5: Zicsr, interrupts,
   dual register-file read) with the interrupt test firmware (sw/irq).

   --invert-luts is the negative test: every LUT is complemented, so the
   run must fail. *)
open! Base
open! Hardcaml
open Stdio
module Bench = Mcu_bench.Bench
module N = Netlist_sim.With_interface (Mcu.I) (Mcu.O)

let () =
  let args = Sys.get_argv () |> Array.to_list |> List.tl_exn in
  let flag f = List.mem args f ~equal:String.equal in
  let positional = List.filter args ~f:(fun a -> not (String.is_prefix a ~prefix:"--")) in
  let firmware, dir =
    match positional with
    | [ f; d ] -> f, d
    | _ ->
      eprintf "usage: main.exe [--invert-luts] [--verilator] FIRMWARE.bin DIR\n";
      Stdlib.exit 2
  in
  Netlist_sim.Ice40_cells.invert_luts := flag "--invert-luts";
  let ecp5 = flag "--ecp5" in
  let config = if ecp5 then Bench.i9 else Bench.icestick in
  let arch = if ecp5 then Netlist_sim.Ecp5 else Ice40 in
  let m, fn =
    N.create ~arch ~dir ~name:"mcu" (Bench.create config (Scope.create ~flatten_design:true ()))
  in
  eprintf
    "netlist: %s\n%!"
    (String.concat ~sep:" "
       (List.map (Netlist_sim.cell_counts m) ~f:(fun (c, n) -> Printf.sprintf "%s=%d" c n)));
  let sim =
    if flag "--verilator"
    then (
      let module Sim = Hardcaml_verilator.With_interface (Mcu.I) (Mcu.O) in
      Sim.create ~verilator_config:Testlib.Verilator_config.config ~clock_names:[ "clock" ] fn)
    else (
      let module Sim = Cyclesim.With_interface (Mcu.I) (Mcu.O) in
      Sim.create fn)
  in
  let image = Bench.firmware firmware in
  let t0 = Unix.gettimeofday () in
  let input, expected, leds =
    if ecp5
    then "irq\r", "irq: timer ok, software ok, ecall ok\r\n> irq\r\nIRQ\r\n> ", 1
    else "hello\rRV32e!\r", "RV32 MCU ready\r\n> hello\r\nHELLO\r\n> RV32e!\r\nRV32E!\r\n> ", 6
  in
  let r = Bench.run config sim ~image ~input ~cycles:200_000 () in
  eprintf "%d cycles in %.1f s\n" r.cycles (Unix.gettimeofday () -. t0);
  match r.mismatch with
  | Some m ->
    eprintf "FAIL netlist lockstep\n%s\n" m;
    Stdlib.exit 1
  | None when String.equal r.output expected && r.leds = leds ->
    eprintf
      "PASS netlist %s (%d instructions, %d interrupts in lockstep)\n"
      (if ecp5 then "ecp5 irq" else "ice40 echo")
      r.retired
      r.interrupts
  | None ->
    eprintf "FAIL netlist echo\n  expected: %S\n  actual:   %S leds=%d\n" expected r.output r.leds;
    Stdlib.exit 1
;;
