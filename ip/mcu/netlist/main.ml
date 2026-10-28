(* Post-synthesis stage (issue #20): synthesise the MCU (iCEstick
   configuration, with the load port) with Yosys `synth_ice40`, read the
   netlist back into HardCaml and run the S1 echo bench on it, including
   lockstep against the golden model.

     main.exe [--invert-luts] [--verilator] FIRMWARE.bin DIR

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
  let config = Bench.icestick in
  let m, fn =
    N.create ~dir ~name:"mcu" (Bench.create config (Scope.create ~flatten_design:true ()))
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
  let r = Bench.run config sim ~image ~input:"hello\rRV32e!\r" ~cycles:200_000 () in
  let expected = "RV32 MCU ready\r\n> hello\r\nHELLO\r\n> RV32e!\r\nRV32E!\r\n> " in
  eprintf "%d cycles in %.1f s\n" r.cycles (Unix.gettimeofday () -. t0);
  match r.mismatch with
  | Some m ->
    eprintf "FAIL netlist lockstep\n%s\n" m;
    Stdlib.exit 1
  | None when String.equal r.output expected && r.leds = 6 ->
    eprintf "PASS netlist echo (%d instructions in lockstep)\n" r.retired
  | None ->
    eprintf "FAIL netlist echo\n  expected: %S\n  actual:   %S leds=%d\n" expected r.output r.leds;
    Stdlib.exit 1
;;
