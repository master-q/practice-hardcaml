(* Print the Verilog for the iCEstick top level to stdout. *)
open! Hardcaml

let () =
  let module C = Circuit.With_interface (Uart.Hello.I) (Uart.Hello.O) in
  let scope = Scope.create ~flatten_design:false () in
  let circuit =
    C.create_exn
      ~name:"top"
      (Uart.Hello.hierarchical
         ~clocks_per_bit:(12_000_000 / 115_200)
         ~gap_bits:23
         ~message:"Hello, iCEstick!\r\n"
         scope)
  in
  Rtl.print ~database:(Scope.circuit_database scope) Verilog circuit
;;
