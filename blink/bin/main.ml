(* Print the Verilog for the iCEstick top level to stdout. *)
open! Hardcaml

let () =
  let module C = Circuit.With_interface (Blink.I) (Blink.O) in
  let scope = Scope.create ~flatten_design:false () in
  let circuit = C.create_exn ~name:"top" (Blink.hierarchical ~counter_bits:26 scope) in
  Rtl.print ~database:(Scope.circuit_database scope) Verilog circuit
;;
