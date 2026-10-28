(* Print the bare rv32 core (no memory, no peripherals) as Verilog, module
   `rv32_core`, for area comparisons: core_verilog.exe rv32i|rv32e *)
open! Base
open! Hardcaml

let () =
  let base : Rv32_model.Isa.base =
    match (Sys.get_argv ()).(1) with
    | "rv32i" -> Rv32i
    | "rv32e" -> Rv32e
    | s -> failwith ("unknown base " ^ s)
  in
  let module C = Circuit.With_interface (Rv32.Core.I) (Rv32.Core.O) in
  let scope = Scope.create ~flatten_design:true () in
  Rtl.print Verilog (C.create_exn ~name:"rv32_core" (Rv32.Core.create ~base scope))
;;
